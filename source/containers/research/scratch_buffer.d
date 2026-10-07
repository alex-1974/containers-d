/**
 * M6 research prototype for one reusable contiguous typed scratch buffer.
 *
 * This module is intentionally not public API. It establishes the semantic
 * baseline before deciding whether ScratchBuffer deserves production
 * promotion and whether a separate UniqueBuffer foundation is justified.
 */
module containers.research.scratch_buffer;

import containers.internal.element_lifetime :
    EndElementLifetimeOps,
    PlacementMoveOps,
    elementHasIndirections,
    elementNeedsDestruction;
import containers.internal.runtime_storage :
    RuntimeStorageAccessOps,
    RuntimeStorageOwner;
import core.lifetime : emplace, forward;
import std.traits : hasIndirections, isNested, Unqual;

/**
 * Reusable fixed-capacity baseline.
 *
 * One allocation is established at construction and retained across reset
 * cycles. Exactly length slots contain live T objects.
 *
 * Stage 1 deliberately has no live reallocation/growth API. This isolates the
 * value of retained reusable storage from the separate ownership/reallocation
 * question tracked by #26.
 */
struct ResearchScratchBuffer(T)
{
    static assert(T.sizeof > 0,
        "ResearchScratchBuffer requires non-zero-size T");
    static assert(!(is(T == struct) && isNested!T && hasIndirections!T),
        "M6 stage 1 does not admit nested/local T with hidden context/indirections");

private:
    mixin PlacementMoveOps!T;
    mixin EndElementLifetimeOps!T;

    RuntimeStorageOwner!T _storage;
    mixin RuntimeStorageAccessOps!T;

    size_t _length;
    size_t _highWater;

    ref T borrowedSlot(
        size_t index) scope return @trusted
    {
        return *runtimeSlotPointer(index);
    }

    ref const(T) borrowedSlot(
        size_t index) const scope return @trusted
    {
        return *runtimeSlotPointer(index);
    }

    void endSlotLifetime(size_t index)
    {
        endElementLifetime(runtimeSlotPointer(index));
        runtimeClearVacatedSlot(index);
    }

public:
    /// Establishes one backing allocation for capacity elements.
    this(size_t capacity)
    {
        _storage.initialize(capacity);
    }

    /// Unique owning storage is never copied implicitly.
    @disable this(ref return scope typeof(this) rhs);

    /**
     * Transfers the backing allocation without relocating live T values.
     *
     * The moved-from source becomes inert.
     */
    this(return scope typeof(this) rhs)
    {
        _storage.takeOwnershipFrom(rhs._storage);
        _length = rhs._length;
        _highWater = rhs._highWater;

        rhs._length = 0;
        rhs._highWater = 0;
    }

    @disable ref typeof(this) opAssign(ref typeof(this) rhs);

    ~this()
    {
        reset();
    }

    /// Backing element capacity retained across reset cycles.
    size_t capacity() const @safe @nogc nothrow
    {
        return _storage.capacity;
    }

    /// Number of currently live elements.
    size_t length() const @safe @nogc nothrow
    {
        return _length;
    }

    /// Maximum live length observed since construction/move.
    size_t highWater() const @safe @nogc nothrow
    {
        return _highWater;
    }

    bool empty() const @safe @nogc nothrow
    {
        return _length == 0;
    }

    bool full() const @safe @nogc nothrow
    {
        return _length == capacity;
    }

    ref T opIndex(size_t index) scope return
    {
        assert(index < _length);
        return borrowedSlot(index);
    }

    ref const(T) opIndex(size_t index) const scope return
    {
        assert(index < _length);
        return borrowedSlot(index);
    }

    /**
     * Borrows the exact live contiguous prefix.
     *
     * Any successful structural mutation, reset, move or destruction
     * invalidates previous borrows.
     */
    pragma(inline, true)
    T[] opSlice()() scope return @trusted @nogc nothrow
    {
        // Empty borrows promise length zero, not a null pointer. Building the
        // slice directly from the owned backing pointer avoids a hot-path
        // empty special case and remains valid for the inert null/zero state.
        return (cast(T*) _storage._bytes.ptr)[0 .. _length];
    }

    pragma(inline, true)
    const(T)[] opSlice()() const scope return @trusted @nogc nothrow
    {
        return (cast(const(T)*) _storage._bytes.ptr)[0 .. _length];
    }

    /**
     * Ensures at least minCapacity backing slots without relocating live T.
     *
     * Returns true when capacity was already sufficient or when an empty
     * buffer successfully established the requested larger capacity.
     *
     * Returns false when growth is required while live elements exist.
     * No allocation or mutation occurs in that case.
     *
     * Successful growth invalidates all previously borrowed slices, including
     * empty borrows. Capacity grows exactly to minCapacity in Stage 2; no
     * geometric growth policy is embedded in the container.
     */
    bool tryReserve(size_t minCapacity) @safe @nogc nothrow
    {
        if (minCapacity <= capacity)
            return true;

        if (!empty)
            return false;

        _storage.replaceEmptyCapacity(minCapacity);
        return true;
    }

    /**
     * Appends one live element when spare established capacity exists.
     *
     * Returns false when full. No allocation or growth is attempted.
     */
    pragma(inline, true)
    bool tryPushBack(U)(auto ref U value)
    if (is(Unqual!U == T) &&
        __traits(compiles, emplace(cast(T*) null, forward!value)))
    {
        if (full)
            return false;

        const index = _length;

        static if (__traits(hasMoveConstructor, T) &&
            is(U == T) &&
            !__traits(isRef, value))
        {
            placementMoveConstruct(runtimeSlotPointer(index), value);
        }
        else
        {
            emplace(runtimeSlotPointer(index), forward!value);
        }

        ++_length;
        if (_length > _highWater)
            _highWater = _length;

        return true;
    }

    /**
     * Ends all live element lifetimes while retaining the backing allocation.
     *
     * No backing allocation or deallocation occurs.
     */
    pragma(inline, true)
    void reset()()
    {
        static if (!elementNeedsDestruction!T &&
            !elementHasIndirections!T)
        {
            // No T lifetime work and no stale GC-visible representation need
            // cleanup. Reuse is therefore an O(1) logical reset.
            _length = 0;
        }
        else
        {
            while (_length != 0)
            {
                --_length;
                endSlotLifetime(_length);
            }
        }
    }
}

version (unittest)
{
    private struct Tracked
    {
        static size_t alive;
        static size_t destroyed;

        int value;

        this(int value)
        {
            this.value = value;
            ++alive;
        }

        this(ref return scope Tracked rhs)
        {
            value = rhs.value;
            ++alive;
        }

        ~this()
        {
            --alive;
            ++destroyed;
        }
    }

    private struct OverAligned
    {
        align(64) ulong value;
    }

    private struct WithIndirection
    {
        Object reference;
        size_t value;
    }
}

unittest
{
    ResearchScratchBuffer!int initial;
    assert(initial.capacity == 0);
    assert(initial.length == 0);
    assert(initial.highWater == 0);
    assert(initial.empty);
    assert(initial.full);
    assert(!initial.tryPushBack(1));
}

unittest
{
    auto scratch = ResearchScratchBuffer!int(4);

    assert(scratch.capacity == 4);
    assert(scratch.tryPushBack(10));
    assert(scratch.tryPushBack(20));
    assert(scratch.tryPushBack(30));

    assert(scratch[] == [10, 20, 30]);
    assert(scratch.highWater == 3);

    const ptrBefore = scratch[].ptr;

    scratch.reset();

    assert(scratch.empty);
    assert(scratch.capacity == 4);
    assert(scratch.highWater == 3);

    assert(scratch.tryPushBack(40));
    assert(scratch[].ptr is ptrBefore);
    assert(scratch[] == [40]);
    assert(scratch.highWater == 3);
}

unittest
{
    ResearchScratchBuffer!int scratch;

    assert(scratch.capacity == 0);
    assert(scratch.tryReserve(8));
    assert(scratch.capacity == 8);
    assert(scratch.empty);

    const firstAddress = scratch[].ptr;

    // No-op reserve keeps established storage.
    assert(scratch.tryReserve(4));
    assert(scratch.capacity == 8);
    assert(scratch[].ptr is firstAddress);

    assert(scratch.tryPushBack(1));
    assert(scratch.tryPushBack(2));

    // Growth is explicitly rejected while T values are live.
    assert(!scratch.tryReserve(16));
    assert(scratch.capacity == 8);
    assert(scratch[] == [1, 2]);

    scratch.reset();

    assert(scratch.tryReserve(16));
    assert(scratch.capacity == 16);
    assert(scratch.empty);

    assert(scratch.tryPushBack(3));
    assert(scratch[] == [3]);
}

unittest
{
    // Empty-only reserve must remain callable from @safe @nogc nothrow code.
    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
            ResearchScratchBuffer!int scratch;

            assert(scratch.tryReserve(32));
            assert(scratch.capacity == 32);
            assert(scratch.tryPushBack(7));

            // Existing capacity does not require relocation.
            assert(scratch.tryReserve(16));

            // Required growth with live data is rejected.
            assert(!scratch.tryReserve(64));

            scratch.reset();
            assert(scratch.tryReserve(64));
        }();
    }));
}

unittest
{
    Tracked.alive = 0;
    Tracked.destroyed = 0;

    {
        auto scratch = ResearchScratchBuffer!Tracked(3);
        auto value = Tracked(7);

        assert(scratch.tryPushBack(value));
        assert(scratch.tryPushBack(value));
        assert(Tracked.alive == 3);

        scratch.reset();
        assert(Tracked.alive == 1);
        assert(Tracked.destroyed == 2);

        assert(scratch.capacity == 3);
    }

    assert(Tracked.alive == 0);
}

unittest
{
    auto scratch = ResearchScratchBuffer!OverAligned(3);

    assert(scratch.tryPushBack(OverAligned(11)));
    assert(scratch.tryPushBack(OverAligned(12)));

    foreach (i; 0 .. scratch.length)
    {
        const address = cast(size_t) &scratch[i];
        assert(address % OverAligned.alignof == 0);
    }
}

unittest
{
    // Reserve preserves over-alignment after backing replacement.
    ResearchScratchBuffer!OverAligned scratch;

    assert(scratch.tryReserve(2));
    assert(scratch.tryPushBack(OverAligned(41)));
    assert((cast(size_t) &scratch[0]) % OverAligned.alignof == 0);

    scratch.reset();
    assert(scratch.tryReserve(5));
    assert(scratch.capacity == 5);

    assert(scratch.tryPushBack(OverAligned(42)));
    assert((cast(size_t) &scratch[0]) % OverAligned.alignof == 0);
}

unittest
{
    // Indirection-bearing storage remains reusable across empty replacement.
    ResearchScratchBuffer!WithIndirection scratch;
    auto object = new Object;

    assert(scratch.tryReserve(1));
    assert(scratch.tryPushBack(WithIndirection(object, 1)));
    assert(scratch[0].reference is object);

    scratch.reset();

    assert(scratch.tryReserve(4));
    assert(scratch.capacity == 4);

    assert(scratch.tryPushBack(WithIndirection(object, 2)));
    assert(scratch[0].reference is object);

    scratch.reset();
    assert(scratch.empty);
}

unittest
{
    static assert(hasIndirections!WithIndirection);

    auto scratch = ResearchScratchBuffer!WithIndirection(2);
    auto object = new Object;

    assert(scratch.tryPushBack(WithIndirection(object, 9)));
    assert(scratch[0].reference is object);

    scratch.reset();

    assert(scratch.empty);
    assert(scratch.capacity == 2);
}

unittest
{
    auto source = ResearchScratchBuffer!int(4);
    assert(source.tryPushBack(1));
    assert(source.tryPushBack(2));

    auto moved = __rvalue(source);

    assert(source.capacity == 0);
    assert(source.length == 0);
    assert(source.highWater == 0);

    assert(moved.capacity == 4);
    assert(moved[] == [1, 2]);
    assert(moved.highWater == 2);
}

unittest
{
    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
            auto scratch = ResearchScratchBuffer!int(8);

            assert(scratch.tryPushBack(1));
            assert(scratch.tryPushBack(2));
            assert(scratch[] == [1, 2]);

            scratch.reset();

            assert(scratch.empty);
            assert(scratch.capacity == 8);
        }();
    }));
}
