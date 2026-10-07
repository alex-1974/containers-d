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
import containers.internal.runtime_storage : RuntimeStorageOwner;
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
    size_t _length;
    size_t _highWater;

    ref T borrowedSlot(
        size_t index) scope return @trusted
    {
        return *_storage.slotPointer(index);
    }

    ref const(T) borrowedSlot(
        size_t index) const scope return @trusted
    {
        return *_storage.slotPointer(index);
    }

    T[] borrowedLiveSlice() scope return @trusted @nogc nothrow
    {
        return _storage.slotSlice(0, _length);
    }

    const(T)[] borrowedLiveSlice() const scope return @trusted @nogc nothrow
    {
        return _storage.slotSlice(0, _length);
    }

    void endSlotLifetime(size_t index)
    {
        endElementLifetime(_storage.slotPointer(index));
        _storage.clearVacatedSlot(index);
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
    T[] opSlice() scope return @trusted @nogc nothrow
    {
        return borrowedLiveSlice();
    }

    const(T)[] opSlice() const scope return @trusted @nogc nothrow
    {
        return borrowedLiveSlice();
    }

    /**
     * Appends one live element when spare established capacity exists.
     *
     * Returns false when full. No allocation or growth is attempted.
     */
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
            placementMoveConstruct(_storage.slotPointer(index), value);
        }
        else
        {
            emplace(_storage.slotPointer(index), forward!value);
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
    void reset()
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
