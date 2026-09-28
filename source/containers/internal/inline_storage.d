/**
 * Fixed-capacity inline raw T-slot storage.
 *
 * This module is package-internal M4.2 research. It owns storage representation
 * and post-lifetime slot sanitation, but it does not own T object lifetimes.
 */
module containers.internal.inline_storage;

import containers.internal.target_capabilities :
    nativePointerAlignment,
    qualifiedInlineEmbeddedAlignment;
import std.traits : hasElaborateDestructor, hasIndirections, isNested;

private alias NativePointer = void*;

/**
 * Raw storage payload with a compiler-visible GC scan shape.
 *
 * When slots can start at a runtime-selected aligned offset, an exact T-array
 * pointer bitmap cannot describe every possible position. In that case an
 * all-pointer-word overlay deliberately makes the payload conservatively
 * scannable.
 */
private union InlineRawStoragePayload(
    T,
    size_t Capacity,
    size_t ByteLength,
    bool ConservativeScan)
{
    static if (hasIndirections!T)
    {
        static if (ConservativeScan || isNested!T)
        {
            enum size_t pointerWordCount =
                (ByteLength + NativePointer.sizeof - 1) /
                NativePointer.sizeof;

            NativePointer[pointerWordCount] conservativeGcShape;
        }
        else
        {
            // Exact scan shape when slot zero is the payload base.
            T[Capacity] gcShape;
        }
    }

    ubyte[ByteLength] bytes;
}

/**
 * Provides Capacity aligned raw slots for T without deciding which slots
 * currently contain live T objects.
 *
 * The representation is selected at compile time from qualified
 * compiler/target capabilities:
 *
 * - when T.alignof is known to propagate correctly through aggregate
 *   embedding, the payload uses the native aligned direct base;
 * - otherwise the storage reserves T.alignof - 1 bytes of slack and derives
 *   an aligned slot base from the actual runtime address.
 *
 * This deliberately permits different machine representations behind the same
 * semantic contract. The ordinary/native-alignment case never pays the dynamic
 * alignment cost.
 *
 * For indirection-bearing T, .init starts from a zeroed GC-visible
 * representation. Dynamically shifted slots use a conservative pointer-word
 * scan shape so every possible pointer-bearing slot location remains visible
 * to the GC. Native direct-base storage retains the exact T[Capacity] scan
 * shape.
 */
package(containers) struct InlineRawStorage(T, size_t Capacity)
{
    static assert(Capacity > 0,
        "InlineRawStorage capacity must be greater than zero");
    static assert(T.sizeof > 0,
        "InlineRawStorage requires an element type with non-zero size");
    static assert((T.alignof & (T.alignof - 1)) == 0,
        "InlineRawStorage requires power-of-two T alignment");

    enum size_t capacity = Capacity;

    /// Exposes the selected representation to package-internal qualification.
    package(containers) enum bool usesDynamicAlignment =
        T.alignof > qualifiedInlineEmbeddedAlignment;

private:
    enum size_t alignmentSlack =
        usesDynamicAlignment ? T.alignof - 1 : 0;

    static assert(
        Capacity <= (size_t.max - alignmentSlack) / T.sizeof,
        "InlineRawStorage byte size overflows size_t");

    enum size_t rawByteLength =
        Capacity * T.sizeof + alignmentSlack;

    alias Payload = InlineRawStoragePayload!(
        T,
        Capacity,
        rawByteLength,
        usesDynamicAlignment);

    static if (usesDynamicAlignment)
    {
        // Do not rely on wrapper over-alignment for compiler/target
        // combinations that have not qualified it. The extra bytes make the
        // actual slot base independent of wrapper placement.
        static if (hasIndirections!T)
            Payload _payload = Payload.init;
        else
            Payload _payload = void;
    }
    else
    {
        // Qualified native embedding keeps the compact direct-base
        // representation with no runtime alignment arithmetic.
        static if (hasIndirections!T)
            align(T.alignof) Payload _payload = Payload.init;
        else
            align(T.alignof) Payload _payload = void;
    }

    size_t slotBaseOffset() const @safe @nogc nothrow
    {
        static if (!usesDynamicAlignment)
        {
            return 0;
        }
        else
        {
            const address = (() @trusted =>
                cast(size_t) _payload.bytes.ptr)();

            const mask = T.alignof - 1;
            const misalignment = address & mask;

            return (T.alignof - misalignment) & mask;
        }
    }

package(containers):
    T* slotPointer(size_t physicalIndex)
        return scope @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        const begin =
            slotBaseOffset() + physicalIndex * T.sizeof;

        assert(begin <= _payload.bytes.length - T.sizeof);

        return (() @trusted =>
            cast(T*) (_payload.bytes.ptr + begin))();
    }

    const(T)* slotPointer(size_t physicalIndex)
        const return scope @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        const begin =
            slotBaseOffset() + physicalIndex * T.sizeof;

        assert(begin <= _payload.bytes.length - T.sizeof);

        return (() @trusted =>
            cast(const(T)*) (_payload.bytes.ptr + begin))();
    }

    T[] slotSlice(size_t physicalStart, size_t count)
        return scope @safe @nogc nothrow
    {
        if (count == 0)
            return null;

        assert(physicalStart < Capacity);
        assert(count <= Capacity - physicalStart);

        return (() @trusted =>
            slotPointer(physicalStart)[0 .. count])();
    }

    const(T)[] slotSlice(size_t physicalStart, size_t count)
        const return scope @safe @nogc nothrow
    {
        if (count == 0)
            return null;

        assert(physicalStart < Capacity);
        assert(count <= Capacity - physicalStart);

        return (() @trusted =>
            slotPointer(physicalStart)[0 .. count])();
    }

    /**
     * Sanitizes one slot after its T lifetime has ended.
     *
     * For pointer-bearing T this removes stale GC roots. Pointer-free storage
     * needs no writes.
     */
    void clearVacatedSlot(size_t physicalIndex)
        @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        static if (hasIndirections!T)
        {
            const begin =
                slotBaseOffset() + physicalIndex * T.sizeof;

            _payload.bytes[begin .. begin + T.sizeof] = 0;
        }
    }
}

version (unittest)
{
    private struct WithIndirection
    {
        Object reference;
        size_t value;
    }

    align(64) private struct OverAligned
    {
        ubyte value;
    }

    align(64) private struct OverAlignedIndirection
    {
        Object reference;
        size_t value;
    }

    private struct IndirectDestructor
    {
        Object reference;

        ~this() {}
    }
}

unittest
{
    alias Storage = InlineRawStorage!(int, 4);

    Storage storage;

    static assert(Storage.capacity == 4);
    static assert(Storage.sizeof == int.sizeof * 4);
    static assert(Storage.alignof >= int.alignof);
    static assert(!Storage.usesDynamicAlignment);
    static assert(!hasIndirections!Storage);

    assert(storage.slotPointer(0) !is null);
    assert(storage.slotPointer(3) !is null);
    assert(storage.slotSlice(0, 4).length == 4);
    assert(storage.slotSlice(0, 0).length == 0);
}

unittest
{
    alias Storage = InlineRawStorage!(WithIndirection, 2);

    static assert(hasIndirections!WithIndirection);
    static assert(hasIndirections!Storage);
    static assert(Storage.alignof >= WithIndirection.alignof);
    static assert(!Storage.usesDynamicAlignment);

    Storage storage;

    // Pointer-bearing native-alignment storage starts from a GC-safe zero
    // representation and retains the exact T scan shape.
    auto bytes = (() @trusted =>
        cast(ubyte*) storage.slotPointer(0))()[
            0 .. WithIndirection.sizeof * 2];

    foreach (value; bytes)
        assert(value == 0);

    bytes[] = 0xA5;
    storage.clearVacatedSlot(1);

    foreach (value; bytes[0 .. WithIndirection.sizeof])
        assert(value == 0xA5);

    foreach (value; bytes[WithIndirection.sizeof .. $])
        assert(value == 0);
}

unittest
{
    alias Storage = InlineRawStorage!(OverAligned, 3);

    struct Holder
    {
        ubyte prefix;
        Storage storage;
    }

    Holder holder;

    static if (Storage.usesDynamicAlignment)
    {
        static assert(Storage.sizeof >=
            OverAligned.sizeof * Storage.capacity +
            OverAligned.alignof - 1);
    }
    else
    {
        static assert(Storage.alignof >= OverAligned.alignof);
        static assert(Storage.sizeof ==
            OverAligned.sizeof * Storage.capacity);
    }

    foreach (i; 0 .. Storage.capacity)
    {
        const address = cast(size_t) holder.storage.slotPointer(i);
        assert(address % OverAligned.alignof == 0);
    }
}

unittest
{
    alias Storage = InlineRawStorage!(OverAlignedIndirection, 2);

    struct Holder
    {
        ubyte prefix;
        Storage storage;
    }

    static assert(hasIndirections!OverAlignedIndirection);
    static assert(hasIndirections!Storage);

    Holder holder;

    foreach (i; 0 .. Storage.capacity)
    {
        const address = cast(size_t) holder.storage.slotPointer(i);
        assert(address % OverAlignedIndirection.alignof == 0);
    }

    // Both representations start from a zeroed GC-visible payload. Dynamic
    // alignment uses a conservative scan shape; native alignment uses T[].
    foreach (value; holder.storage._payload.bytes)
        assert(value == 0);
}

unittest
{
    alias Storage = InlineRawStorage!(IndirectDestructor, 2);

    static assert(hasIndirections!IndirectDestructor);
    static assert(hasElaborateDestructor!IndirectDestructor);

    // Raw storage owns bytes, not T lifetimes. The union scan-shape member must
    // therefore not make the storage wrapper itself automatically destroy
    // potential T slots.
    static assert(!hasElaborateDestructor!Storage);
}
