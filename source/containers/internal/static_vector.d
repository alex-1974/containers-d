/**
 * Package-internal implementation of the fixed-capacity vector family.
 *
 * The stable public alias is exported by `containers.static_vector`; this module
 * owns implementation details so the public surface stays narrow.
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
 * Initial family constraints:
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
        "StaticVector does not support nested/local struct element types with hidden context/indirections");

    enum size_t capacity = Capacity;

private:
    /*
     * Scalar T does not need explicit raw-lifetime machinery. Keep the ordinary
     * static-array representation so common numeric/pointer specializations
     * compile as cheaply as the consumer-local baseline.
     *
     * Non-scalar T retains the audited M4.2 raw-storage/lifetime path.
     */
    enum bool useDirectScalarStorage =
        __traits(isScalar, T);

    static if (useDirectScalarStorage)
    {
        T[Capacity] _directData;
    }
    else
    {
        // Non-scalar storage requires explicit lifetime and GC/alignment
        // handling. Generate the qualified storage operations in this
        // aggregate so DMD 2.111 can inline the hot accessors.
        mixin InlineRawStorageOps!(T, Capacity);
    }

    size_t _length;

    static if (useDirectScalarStorage)
    {
        enum bool needsCustomTransfer = false;

        void endLiveSlot()(size_t physicalIndex)
        {
            assert(physicalIndex < Capacity);

            static if (elementHasIndirections!T)
                _directData[physicalIndex] = T.init;
        }
    }
    else
    {
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
    }

public:
    pragma(inline, true)
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _length;
    }

    pragma(inline, true)
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

        static if (useDirectScalarStorage)
            return _directData[0];
        else
            return *slotPointer(0);
    }

    ref const(T) front() const
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);

        static if (useDirectScalarStorage)
            return _directData[0];
        else
            return *slotPointer(0);
    }

    ref T back()
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);

        static if (useDirectScalarStorage)
            return _directData[_length - 1];
        else
            return *slotPointer(_length - 1);
    }

    ref const(T) back() const
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);

        static if (useDirectScalarStorage)
            return _directData[_length - 1];
        else
            return *slotPointer(_length - 1);
    }

    pragma(inline, true)
    ref T opIndex(size_t index)
        return scope pure nothrow @safe @nogc
    {
        assert(index < _length);

        static if (useDirectScalarStorage)
            return _directData[index];
        else
            return *slotPointer(index);
    }

    pragma(inline, true)
    ref const(T) opIndex(size_t index) const
        return scope pure nothrow @safe @nogc
    {
        assert(index < _length);

        static if (useDirectScalarStorage)
            return _directData[index];
        else
            return *slotPointer(index);
    }

    pragma(inline, true)
    T[] opSlice()
        return scope pure nothrow @safe @nogc
    {
        static if (useDirectScalarStorage)
            return _directData[0 .. _length];
        else
            return slotSlice(0, _length);
    }

    pragma(inline, true)
    const(T)[] opSlice() const
        return scope pure nothrow @safe @nogc
    {
        static if (useDirectScalarStorage)
            return _directData[0 .. _length];
        else
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
    static if (useDirectScalarStorage)
    {
        pragma(inline, true)
        void pushBack(T value)
            pure nothrow @safe @nogc
        {
            assert(!full);

            _directData[_length] = value;
            ++_length;
        }

        pragma(inline, true)
        bool tryPushBack(T value)
            pure nothrow @safe @nogc
        {
            if (full)
                return false;

            _directData[_length] = value;
            ++_length;
            return true;
        }
    }
    else
    {
        pragma(inline, true)
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

            static if (hasLanguageMoveConstructor!T &&
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
    }

    void popBack()()
    {
        assert(!empty);

        --_length;
        endLiveSlot!()(_length);
    }

    pragma(inline, true)
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
        assert(vector[] == [1.0, 2.0]);

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
    assert(vector[] == [10, 20]);

    vector.popBack();
    assert(vector[] == [10]);
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
