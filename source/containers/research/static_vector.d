/**
 * Research-only import surface for the M4.3 StaticVector candidate.
 *
 * This module exists only to let real external consumers qualify the candidate
 * before any package-root/public-release decision. Importing this module is not
 * a compatibility promise.
 */
module containers.research.static_vector;

import containers.internal.static_vector :
    InternalStaticVector = StaticVector;

/// Research alias for the package-internal M4.3 candidate.
alias StaticVector = InternalStaticVector;


/**
 * Research-only scalar fixed-vector composition surface.
 *
 * This mixin exists to test advanced consumer adaptation without an owning
 * wrapper layer. It injects its own state and does not depend on host fields.
 *
 * Scope is deliberately narrow during M4.3:
 * - scalar T only;
 * - fixed positive capacity;
 * - no element lifetime/destructor machinery is required.
 *
 * It is not a compatibility promise.
 */
mixin template ScalarStaticVectorOps(T, size_t Capacity)
if (__traits(isScalar, T) && Capacity > 0)
{
    enum size_t capacity = Capacity;

private:
    T[Capacity] _staticVectorData;
    size_t _staticVectorLength;

public:
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _staticVectorLength;
    }

    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _staticVectorLength == 0;
    }

    @property bool full() const
        pure nothrow @safe @nogc
    {
        return _staticVectorLength == Capacity;
    }

    ref T front()
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return _staticVectorData[0];
    }

    ref const(T) front() const
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return _staticVectorData[0];
    }

    ref T back()
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return _staticVectorData[_staticVectorLength - 1];
    }

    ref const(T) back() const
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return _staticVectorData[_staticVectorLength - 1];
    }

    ref T opIndex(size_t index)
        return scope pure nothrow @safe @nogc
    {
        assert(index < _staticVectorLength);
        return _staticVectorData[index];
    }

    ref const(T) opIndex(size_t index) const
        return scope pure nothrow @safe @nogc
    {
        assert(index < _staticVectorLength);
        return _staticVectorData[index];
    }

    T[] asSlice()
        return scope pure nothrow @safe @nogc
    {
        return _staticVectorData[0 .. _staticVectorLength];
    }

    const(T)[] asSlice() const
        return scope pure nothrow @safe @nogc
    {
        return _staticVectorData[0 .. _staticVectorLength];
    }

    pragma(inline, true)
    void pushBack(T value)
        pure nothrow @safe @nogc
    {
        assert(!full);

        _staticVectorData[_staticVectorLength] = value;
        ++_staticVectorLength;
    }

    bool tryPushBack(T value)
        pure nothrow @safe @nogc
    {
        if (full)
            return false;

        pushBack(value);
        return true;
    }

    void popBack()
        pure nothrow @safe @nogc
    {
        assert(!empty);
        --_staticVectorLength;
    }

    pragma(inline, true)
    void clear()
        pure nothrow @safe @nogc
    {
        _staticVectorLength = 0;
    }
}

unittest
{
    struct ScalarConsumer
    {
        mixin ScalarStaticVectorOps!(double, 4);
    }

    static assert(ScalarConsumer.sizeof ==
        4 * double.sizeof + size_t.sizeof);

    ScalarConsumer values;

    values.pushBack(1.0);
    values.pushBack(2.0);

    assert(values.length == 2);
    assert(values[0] == 1.0);
    assert(values[1] == 2.0);

    values.clear();
    assert(values.empty);
}
