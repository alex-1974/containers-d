/**
 * Internal owning runtime storage for the runtime-capacity ring buffer.
 *
 * This module is an implementation detail of containers-d and is not exported
 * from the package root.
 */
module containers.internal.runtime_storage;

import core.exception : onOutOfMemoryError;
import core.memory : GC;
import std.experimental.allocator.mallocator : AlignedMallocator;
import std.traits : hasIndirections;

private enum uint storageAlignment(T) =
    cast(uint) (T.alignof > AlignedMallocator.alignment
        ? T.alignof
        : AlignedMallocator.alignment);

private bool checkedStorageBytes(T)(
    size_t capacity,
    out size_t bytes) @safe @nogc nothrow
{
    if (capacity > size_t.max / T.sizeof)
    {
        bytes = 0;
        return false;
    }

    bytes = capacity * T.sizeof;
    return true;
}

private void addGcRange(scope ubyte[] bytes) @trusted @nogc nothrow
{
    assert(bytes.length != 0);
    GC.addRange(bytes.ptr, bytes.length);
}

private void removeGcRange(scope ubyte[] bytes) @trusted @nogc nothrow
{
    assert(bytes.length != 0);
    GC.removeRange(bytes.ptr);
}

private struct AlignedStorageBackend
{
    static ubyte[] acquire(
        size_t bytes,
        uint alignment) @trusted @nogc nothrow
    {
        auto block = AlignedMallocator.instance.alignedAllocate(
            bytes,
            alignment);

        return cast(ubyte[]) block;
    }

    static void release(scope ubyte[] block) @trusted @nogc nothrow
    {
        if (block.ptr is null)
            return;

        AlignedMallocator.instance.deallocate(cast(void[]) block);
    }
}

/**
 * Move-only owner for one aligned runtime storage block.
 *
 * The owner manages storage bytes only. It does not know which slots currently
 * contain live T objects; the enclosing container owns that element-lifetime
 * accounting.
 */
package(containers) struct RuntimeStorageOwner(
    T,
    Backend = AlignedStorageBackend)
{
private:
    ubyte[] _bytes;
    size_t _capacity;

    void registerRangeIfNeeded() scope @safe @nogc nothrow
    {
        static if (hasIndirections!T)
        {
            if (_bytes.ptr !is null)
            {
                // Registered external memory is scanned conservatively. Start
                // with no stale pointer representations in unused slots.
                _bytes[] = 0;
                addGcRange(_bytes);
            }
        }
    }

    void unregisterRangeIfNeeded() scope @safe @nogc nothrow
    {
        static if (hasIndirections!T)
        {
            if (_bytes.ptr !is null)
                removeGcRange(_bytes);
        }
    }

    void releaseStorage() scope @safe @nogc nothrow
    {
        if (_bytes.ptr is null)
            return;

        unregisterRangeIfNeeded();

        // Backend release may be @system because aliases could dangle. The
        // owner invariant guarantees unique storage ownership; all borrowed
        // views must already be invalid by the time the owner releases.
        Backend.release(_bytes);

        _bytes = null;
        _capacity = 0;
    }

public:
    /**
     * Acquires storage for capacity T slots.
     *
     * Capacity zero is the inert, allocation-free owner state.
     */
    this(size_t capacity) @safe @nogc nothrow
    {
        if (capacity == 0)
            return;

        size_t bytes;
        if (!checkedStorageBytes!T(capacity, bytes))
            onOutOfMemoryError();

        auto block = Backend.acquire(bytes, storageAlignment!T);
        if (block.ptr is null)
            onOutOfMemoryError();

        _bytes = block;
        _capacity = capacity;
        registerRangeIfNeeded();
    }

    /// Owning storage is never copied implicitly.
    @disable this(ref return scope typeof(this) rhs);

    /**
     * Transfers the backing allocation in O(1).
     *
     * The storage address does not change, so any live T objects would remain
     * at the same addresses. GC range registration, when present, remains on
     * that same allocation and transfers with ownership.
     */
    this(return scope typeof(this) rhs) @safe @nogc nothrow
    {
        _bytes = rhs._bytes;
        _capacity = rhs._capacity;

        rhs._bytes = null;
        rhs._capacity = 0;
    }

    /// Identity assignment is deliberately unavailable in the first owner.
    @disable ref typeof(this) opAssign(ref typeof(this) rhs);

    ~this() scope @safe @nogc nothrow
    {
        releaseStorage();
    }

    /// Number of T slots represented by the backing block.
    size_t capacity() const @safe @nogc nothrow
    {
        return _capacity;
    }

    /// Whether this owner holds no backing allocation.
    bool emptyStorage() const @safe @nogc nothrow
    {
        return _bytes.ptr is null;
    }

    /// Byte size of the owned raw block.
    size_t byteLength() const @safe @nogc nothrow
    {
        return _bytes.length;
    }

    /**
     * Clears one no-longer-live slot when T can contain GC-visible
     * indirections.
     *
     * Call only after the T lifetime in that slot has ended.
     */
    void clearVacatedSlot(size_t physicalIndex) @safe @nogc nothrow
    {
        assert(physicalIndex < _capacity);

        static if (hasIndirections!T)
        {
            const begin = physicalIndex * T.sizeof;
            _bytes[begin .. begin + T.sizeof] = 0;
        }
    }
}

version (unittest)
{
    private struct CountingStorageBackend
    {
        static size_t acquisitions;
        static size_t releases;

        static ubyte[] acquire(
            size_t bytes,
            uint alignment) @safe @nogc nothrow
        {
            ++acquisitions;
            return AlignedStorageBackend.acquire(bytes, alignment);
        }

        static void release(scope ubyte[] block) @safe @nogc nothrow
        {
            ++releases;
            AlignedStorageBackend.release(block);
        }

        static void reset() @safe @nogc nothrow
        {
            acquisitions = 0;
            releases = 0;
        }
    }

    private struct WithIndirection
    {
        Object reference;
        size_t value;
    }

    private struct OverAligned
    {
        align(64) ubyte value;
    }
}

unittest
{
    // .init and explicit capacity zero are the same inert owner state.
    RuntimeStorageOwner!int initial;
    assert(initial.capacity == 0);
    assert(initial.byteLength == 0);
    assert(initial.emptyStorage);

    auto zero = RuntimeStorageOwner!int(0);
    assert(zero.capacity == 0);
    assert(zero.byteLength == 0);
    assert(zero.emptyStorage);
}

unittest
{
    // Positive capacity performs exactly one acquisition, and O(1) move
    // transfers the one release responsibility to the destination owner.
    alias Owner = RuntimeStorageOwner!(int, CountingStorageBackend);

    CountingStorageBackend.reset();

    {
        auto source = Owner(17);

        assert(CountingStorageBackend.acquisitions == 1);
        assert(CountingStorageBackend.releases == 0);
        assert(source.capacity == 17);
        assert(source.byteLength == 17 * int.sizeof);
        assert(!source.emptyStorage);

        auto moved = __rvalue(source);

        assert(source.capacity == 0);
        assert(source.byteLength == 0);
        assert(source.emptyStorage);

        assert(moved.capacity == 17);
        assert(moved.byteLength == 17 * int.sizeof);
        assert(!moved.emptyStorage);

        assert(CountingStorageBackend.acquisitions == 1);
        assert(CountingStorageBackend.releases == 0);
    }

    assert(CountingStorageBackend.acquisitions == 1);
    assert(CountingStorageBackend.releases == 1);
}

unittest
{
    // Copying an owning allocation would either alias ownership or allocate a
    // hidden deep copy; both are deliberately rejected.
    alias Owner = RuntimeStorageOwner!int;

    static assert(!__traits(compiles, {
        Owner source;
        Owner copy = source;
    }));

    static assert(!__traits(compiles, {
        Owner source;
        Owner target;
        target = source;
    }));
}

unittest
{
    // Byte-size overflow is detected before any allocation attempt.
    size_t bytes;

    assert(checkedStorageBytes!long(0, bytes));
    assert(bytes == 0);

    assert(checkedStorageBytes!long(7, bytes));
    assert(bytes == 7 * long.sizeof);

    assert(!checkedStorageBytes!long(size_t.max, bytes));
    assert(bytes == 0);
}

unittest
{
    // The backing address satisfies both allocator and over-aligned T needs.
    auto owner = RuntimeStorageOwner!OverAligned(3);

    assert(owner.capacity == 3);
    assert(owner.byteLength == 3 * OverAligned.sizeof);
    assert(owner._bytes.ptr !is null);
    assert((cast(size_t) owner._bytes.ptr) % OverAligned.alignof == 0);
    assert((cast(size_t) owner._bytes.ptr)
        % AlignedMallocator.alignment == 0);
}

unittest
{
    // Registered storage for indirection-bearing elements starts with no stale
    // pointer representations and vacated slots are explicitly cleared.
    static assert(hasIndirections!WithIndirection);

    auto owner = RuntimeStorageOwner!WithIndirection(2);

    foreach (value; owner._bytes)
        assert(value == 0);

    owner._bytes[] = 0xA5;
    owner.clearVacatedSlot(1);

    foreach (value; owner._bytes[0 .. WithIndirection.sizeof])
        assert(value == 0xA5);

    foreach (value; owner._bytes[WithIndirection.sizeof .. $])
        assert(value == 0);
}

unittest
{
    // The owner lifecycle itself is usable from @safe @nogc nothrow code.
    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
            auto source = RuntimeStorageOwner!int(8);
            auto moved = __rvalue(source);

            assert(source.emptyStorage);
            assert(moved.capacity == 8);
        }();
    }));
}
