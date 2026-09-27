/**
 * Fixed-capacity inline raw T-slot storage.
 *
 * This module is package-internal M4.2 research. It owns storage representation
 * and post-lifetime slot sanitation, but it does not own T object lifetimes.
 */
module containers.internal.inline_storage;

import std.traits : hasElaborateDestructor, hasIndirections, isNested;

/**
 * Raw storage payload with a compiler-visible GC scan shape.
 *
 * The T array is never used as an owning array of live T objects. It exists
 * solely so the compiler can describe possible T pointer offsets to the GC.
 * Live T lifetimes are begun and ended explicitly through the byte view.
 */
private union InlineRawStoragePayload(T, size_t Capacity)
{
    static if (hasIndirections!T)
    {
        static if (isNested!T)
        {
            // Embedding a nested T can carry its hidden context into the
            // aggregate. Preserve the existing StaticRingBuffer conservative
            // scan shape while nested-element semantics remain separate
            // research.
            void[T.sizeof * Capacity] conservativeGcShape;
        }
        else
        {
            T[Capacity] gcShape;
        }
    }

    align(T.alignof) ubyte[T.sizeof * Capacity] bytes;
}

/**
 * Provides Capacity aligned raw slots for T without deciding which slots
 * currently contain live T objects.
 *
 * For indirection-bearing T, .init starts from a zeroed GC-visible
 * representation. For pointer-free T, the bytes remain uninitialized until an
 * element lifetime is explicitly begun.
 */
package(containers) struct InlineRawStorage(T, size_t Capacity)
{
    static assert(Capacity > 0,
        "InlineRawStorage capacity must be greater than zero");
    static assert(T.sizeof > 0,
        "InlineRawStorage requires an element type with non-zero size");

    enum size_t capacity = Capacity;

private:
    alias Payload = InlineRawStoragePayload!(T, Capacity);

    static if (hasIndirections!T)
        Payload _payload = Payload.init;
    else
        Payload _payload = void;

package(containers):
    T* slotPointer(size_t physicalIndex)
        return scope @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        return (() @trusted =>
            cast(T*) (_payload.bytes.ptr + physicalIndex * T.sizeof))();
    }

    const(T)* slotPointer(size_t physicalIndex)
        const return scope @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        return (() @trusted =>
            cast(const(T)*) (_payload.bytes.ptr +
                physicalIndex * T.sizeof))();
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
            const begin = physicalIndex * T.sizeof;
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

    private struct OverAligned
    {
        align(64) ubyte value;
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

    // Pointer-bearing inline storage starts from a GC-safe zero
    // representation.
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

    Storage storage;

    static assert(Storage.alignof >= OverAligned.alignof);

    foreach (i; 0 .. Storage.capacity)
    {
        const address = cast(size_t) storage.slotPointer(i);
        assert(address % OverAligned.alignof == 0);
    }
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
