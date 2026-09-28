/**
 * Package-internal M4.3 fixed-capacity vector prototype.
 *
 * This is not a public containers-d API yet. It exists to test whether the
 * common lifetime/storage foundation can replace duplicated fixed inline
 * buffers without changing consumer hot-path quality.
 */
module containers.internal.static_vector;

import containers.internal.element_lifetime :
    EndElementLifetimeOps,
    PlacementMoveOps,
    elementCopyConstructible,
    elementHasIndirections,
    elementNeedsDestruction,
    hasLanguageMoveConstructor;
import containers.internal.inline_storage : InlineRawStorageOps;

import core.lifetime : emplace, forward, moveEmplace;
import std.traits :
    Unqual,
    hasElaborateCopyConstructor,
    hasElaborateDestructor,
    hasElaborateMove,
    hasIndirections,
    isNested;

/**
 * Fixed-capacity contiguous vector with inline storage.
 *
 * Exactly length slots contain live T values. Capacity is known at compile
 * time and the container itself never allocates.
 *
 * Research constraints:
 * - Capacity must be greater than zero;
 * - nested/local structs with hidden indirections remain excluded while issue
 *   #10 is unresolved;
 * - identity assignment for element types requiring custom transfer remains
 *   disabled in this prototype.
 */
package(containers) struct StaticVector(T, size_t Capacity)
if (Capacity > 0)
{
    static assert(T.sizeof > 0,
        "StaticVector requires an element type with non-zero size");
    static assert(!(is(T == struct) && isNested!T && hasIndirections!T),
        "StaticVector research prototype does not yet support nested/local struct element types with hidden context/indirections");

    enum size_t capacity = Capacity;

private:
    // Generate the inline storage state/accessors in this aggregate. This is
    // performance-significant on DMD 2.111; see the M4.3 expansion probe.
    mixin InlineRawStorageOps!(T, Capacity);

    size_t _length;

    mixin PlacementMoveOps!T;
    mixin EndElementLifetimeOps!T;

    enum bool needsCustomTransfer =
        !elementCopyConstructible!T ||
        hasElaborateCopyConstructor!T ||
        hasElaborateDestructor!T ||
        hasElaborateMove!T ||
        hasLanguageMoveConstructor!T;

    void endLiveSlot()(size_t physicalIndex)
    {
        static if (elementNeedsDestruction!T)
            endElementLifetime(slotPointer(physicalIndex));

        static if (elementHasIndirections!T)
            clearVacatedSlot(physicalIndex);
    }

public:
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _length;
    }

    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _length == 0;
    }

    @property bool full() const
        pure nothrow @safe @nogc
    {
        return _length == Capacity;
    }

    ref T front()
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return *slotPointer(0);
    }

    ref const(T) front() const
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return *slotPointer(0);
    }

    ref T back()
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return *slotPointer(_length - 1);
    }

    ref const(T) back() const
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return *slotPointer(_length - 1);
    }

    ref T opIndex(size_t index)
        return scope pure nothrow @safe @nogc
    {
        assert(index < _length);
        return *slotPointer(index);
    }

    ref const(T) opIndex(size_t index) const
        return scope pure nothrow @safe @nogc
    {
        assert(index < _length);
        return *slotPointer(index);
    }

    T[] asSlice()
        return scope pure nothrow @safe @nogc
    {
        return slotSlice(0, _length);
    }

    const(T)[] asSlice() const
        return scope pure nothrow @safe @nogc
    {
        return slotSlice(0, _length);
    }

    /**
     * Appends one value.
     *
     * Precondition: spare capacity exists.
     *
     * This is deliberately the precondition-based primitive needed by the
     * geo-d/geo3-d ExpansionBuffer consumer. A checked tryPushBack wrapper is
     * provided separately so the hot path need not pay a full-capacity branch
     * after assertions are removed.
     */
    void pushBack(U)(auto ref U value)
    if (is(Unqual!U == T) &&
        (
            (hasLanguageMoveConstructor!T &&
                is(U == T) &&
                !__traits(isRef, value)) ||
            __traits(compiles,
                emplace(cast(T*) null, forward!value))
        ))
    {
        assert(!full);

        static if (__traits(isScalar, T))
        {
            // For scalar values the destination slot needs no language-level
            // construction machinery. Keeping this assignment local avoids
            // DMD 2.111's measured non-inlined core.lifetime.emplaceRef path.
            *slotPointer(_length) = value;
        }
        else static if (hasLanguageMoveConstructor!T &&
            is(U == T) &&
            !__traits(isRef, value))
        {
            placementMoveConstruct(
                slotPointer(_length),
                value);
        }
        else
        {
            emplace(
                slotPointer(_length),
                forward!value);
        }

        ++_length;
    }

    bool tryPushBack(U)(auto ref U value)
    if (is(Unqual!U == T) &&
        (
            (hasLanguageMoveConstructor!T &&
                is(U == T) &&
                !__traits(isRef, value)) ||
            __traits(compiles,
                emplace(cast(T*) null, forward!value))
        ))
    {
        if (full)
            return false;

        pushBack(forward!value);
        return true;
    }

    void popBack()()
    {
        assert(!empty);

        --_length;
        endLiveSlot!()(_length);
    }

    void clear()()
    {
        static if (elementNeedsDestruction!T ||
            elementHasIndirections!T)
        {
            while (_length != 0)
            {
                --_length;
                endLiveSlot!()(_length);
            }
        }
        else
        {
            // Trivial/pointer-free elements need no per-slot work.
            _length = 0;
        }
    }

    static if (needsCustomTransfer)
    {
        static if (elementCopyConstructible!T)
        {
            this(ref return scope typeof(this) rhs)
            {
                scope(failure) clear();

                foreach (index; 0 .. rhs._length)
                {
                    emplace(
                        slotPointer(_length),
                        *rhs.slotPointer(index));
                    ++_length;
                }
            }
        }
        else
        {
            @disable this(ref return scope typeof(this) rhs);
        }

        this(return scope typeof(this) rhs)
        {
            scope(failure) clear();

            foreach (index; 0 .. rhs._length)
            {
                auto source =
                    rhs.slotPointer(index);
                auto target =
                    slotPointer(_length);

                static if (hasLanguageMoveConstructor!T)
                    placementMoveConstruct(target, *source);
                else
                    moveEmplace(*source, *target);

                ++_length;
            }

            rhs.clear();
        }

        @disable ref typeof(this) opAssign(
            ref typeof(this) rhs);
    }

    static if (elementNeedsDestruction!T)
    {
        ~this()
        {
            clear();
        }
    }
}

version (unittest)
{
    private struct Tracked
    {
        static int alive;
        static int destroyed;

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

    private struct MoveOnly
    {
        int value;

        this(int value)
        {
            this.value = value;
        }

        @disable this(ref return scope MoveOnly rhs);

        this(return scope MoveOnly rhs) @safe @nogc nothrow
        {
            value = rhs.value;
            rhs.value = -1;
        }
    }

    private void binary64ContractProbe(
        ref StaticVector!(double, 4) vector)
        pure nothrow @safe @nogc
    {
        assert(vector.empty);
        vector.pushBack(1.0);
        vector.pushBack(2.0);

        assert(vector.length == 2);
        assert(vector[0] == 1.0);
        assert(vector[1] == 2.0);
        assert(vector.front == 1.0);
        assert(vector.back == 2.0);
        assert(vector.asSlice == [1.0, 2.0]);

        vector.popBack();
        assert(vector.length == 1);

        vector.clear();
        assert(vector.empty);
    }
}

unittest
{
    StaticVector!(double, 4) vector;
    binary64ContractProbe(vector);

    static assert(StaticVector!(double, 4).capacity == 4);
    static assert(
        StaticVector!(double, 4).sizeof ==
        4 * double.sizeof + size_t.sizeof);
}

unittest
{
    StaticVector!(int, 2) vector;

    assert(vector.tryPushBack(10));
    assert(vector.tryPushBack(20));
    assert(!vector.tryPushBack(30));

    assert(vector.full);
    assert(vector.asSlice == [10, 20]);

    vector.popBack();
    assert(vector.asSlice == [10]);
}

unittest
{
    Tracked.alive = 0;
    Tracked.destroyed = 0;

    {
        StaticVector!(Tracked, 3) vector;

        auto first = Tracked(11);
        auto second = Tracked(22);

        vector.pushBack(first);
        vector.pushBack(second);

        assert(vector.length == 2);

        vector.popBack();
        assert(vector.length == 1);

        vector.clear();
        assert(vector.empty);
    }

    assert(Tracked.alive == 0);
    assert(Tracked.destroyed >= 2);
}

unittest
{
    StaticVector!(MoveOnly, 2) vector;

    assert(vector.tryPushBack(MoveOnly(7)));
    assert(vector.front.value == 7);

    auto moved = __rvalue(vector);

    assert(vector.empty);
    assert(moved.length == 1);
    assert(moved.front.value == 7);
}
