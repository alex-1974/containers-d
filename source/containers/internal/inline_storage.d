/**
 * Fixed-capacity inline raw T-slot storage.
 *
 * This module is package-internal M4.2/M4.3 research. It owns storage
 * representation and post-lifetime slot sanitation, but it does not own T
 * object lifetimes.
 */
module containers.internal.inline_storage;

import std.traits : hasElaborateDestructor, hasIndirections, isNested;

private enum size_t nativePointerAlignment = (void*).alignof;

/**
 * Injects fixed-capacity raw storage and slot access into the consuming
 * aggregate.
 *
 * This typed state+ops mixin exists for a measured compiler reason: DMD 2.111
 * does not inline the equivalent imported InlineRawStorage.slotPointer calls in
 * the StaticVector hot path, while LDC 1.41 does. Local generation lets a
 * container family share one storage implementation without paying runtime
 * calls merely because the implementation lives in another module.
 *
 * The mixin injects:
 * - one raw payload field;
 * - local alignment calculation;
 * - slotPointer/slotSlice;
 * - clearVacatedSlot.
 *
 * It does not decide which slots contain live T objects.
 */
package(containers) mixin template InlineRawStorageOps(
    T,
    size_t Capacity,
    bool HasIndirections = hasIndirections!T,
    bool IsNested = isNested!T,
    size_t NativeAlignment = nativePointerAlignment)
{
    static assert(Capacity > 0,
        "Inline raw storage capacity must be greater than zero");
    static assert(T.sizeof > 0,
        "Inline raw storage requires an element type with non-zero size");
    static assert((T.alignof & (T.alignof - 1)) == 0,
        "Inline raw storage requires power-of-two T alignment");

private:
    enum bool needsDynamicAlignment =
        T.alignof > NativeAlignment;

    enum size_t alignmentSlack =
        needsDynamicAlignment ? T.alignof - 1 : 0;

    static assert(
        Capacity <= (size_t.max - alignmentSlack) / T.sizeof,
        "Inline raw storage byte size overflows size_t");

    enum size_t rawByteLength =
        Capacity * T.sizeof + alignmentSlack;

    /**
     * Raw payload with a compiler-visible GC scan shape.
     *
     * When slot zero can move inside the payload at runtime, an exact T-array
     * bitmap cannot describe every possible pointer position. Use a
     * conservative pointer-word overlay in that case.
     */
    union InlinePayload
    {
        static if (HasIndirections)
        {
            static if (needsDynamicAlignment || IsNested)
            {
                enum size_t pointerWordCount =
                    (rawByteLength + (void*).sizeof - 1) /
                    (void*).sizeof;

                void*[pointerWordCount] conservativeGcShape;
            }
            else
            {
                T[Capacity] gcShape;
            }
        }

        ubyte[rawByteLength] bytes;
    }

    static if (needsDynamicAlignment)
    {
        // Do not rely on enclosing aggregate over-alignment. DMD 2.111 does
        // not propagate that guarantee reliably. Slack below lets slot zero be
        // aligned from the actual runtime address.
        static if (HasIndirections)
            InlinePayload _payload = InlinePayload.init;
        else
            InlinePayload _payload = void;
    }
    else
    {
        static if (HasIndirections)
            align(T.alignof) InlinePayload _payload = InlinePayload.init;
        else
            align(T.alignof) InlinePayload _payload = void;
    }

    size_t slotBaseOffset() const
        pure @safe @nogc nothrow
    {
        static if (!needsDynamicAlignment)
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
        return scope pure @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        const begin =
            slotBaseOffset() + physicalIndex * T.sizeof;

        assert(begin <= _payload.bytes.length - T.sizeof);

        return (() @trusted =>
            cast(T*) (_payload.bytes.ptr + begin))();
    }

    const(T)* slotPointer(size_t physicalIndex)
        const return scope pure @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        const begin =
            slotBaseOffset() + physicalIndex * T.sizeof;

        assert(begin <= _payload.bytes.length - T.sizeof);

        return (() @trusted =>
            cast(const(T)*) (_payload.bytes.ptr + begin))();
    }

    T[] slotSlice(size_t physicalStart, size_t count)
        return scope pure @safe @nogc nothrow
    {
        if (count == 0)
            return null;

        assert(physicalStart < Capacity);
        assert(count <= Capacity - physicalStart);

        return (() @trusted =>
            slotPointer(physicalStart)[0 .. count])();
    }

    const(T)[] slotSlice(size_t physicalStart, size_t count)
        const return scope pure @safe @nogc nothrow
    {
        if (count == 0)
            return null;

        assert(physicalStart < Capacity);
        assert(count <= Capacity - physicalStart);

        return (() @trusted =>
            slotPointer(physicalStart)[0 .. count])();
    }

    void clearVacatedSlot(size_t physicalIndex)
        pure @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        static if (HasIndirections)
        {
            const begin =
                slotBaseOffset() + physicalIndex * T.sizeof;

            _payload.bytes[begin .. begin + T.sizeof] = 0;
        }
    }
}

/**
 * Standalone raw-slot storage wrapper.
 *
 * Family containers that need DMD-local code generation can mix
 * InlineRawStorageOps directly into their own aggregate. This wrapper remains
 * useful for composition, structural-contract tests and consumers that prefer
 * an explicit storage object.
 */
package(containers) struct InlineRawStorage(T, size_t Capacity)
if (Capacity > 0)
{
    enum size_t capacity = Capacity;

    mixin InlineRawStorageOps!(T, Capacity);
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

    Storage storage;

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

    static assert(Storage.sizeof >=
        OverAligned.sizeof * Storage.capacity +
        OverAligned.alignof - 1);

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

    foreach (value; holder.storage._payload.bytes)
        assert(value == 0);
}

unittest
{
    alias Storage = InlineRawStorage!(IndirectDestructor, 2);

    static assert(hasIndirections!IndirectDestructor);
    static assert(hasElaborateDestructor!IndirectDestructor);
    static assert(!hasElaborateDestructor!Storage);
}
