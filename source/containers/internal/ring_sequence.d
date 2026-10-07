/**
 * Package-internal ring sequencing mechanics.
 *
 * This M4.4 research mixin owns only logical ring state and wrap sequencing.
 * It deliberately knows nothing about storage, T lifetime, ownership,
 * allocation, borrowing, or synchronization.
 */
module containers.internal.ring_sequence;

/**
 * Injects the two-word ring sequence state and its common sequencing
 * operations into a consuming ring family.
 *
 * StaticCapacity == 0 selects runtime-capacity semantics and resolves the
 * consuming aggregate's `capacity` property locally. A positive
 * StaticCapacity keeps compile-time wrap specialization available.
 */
package(containers) mixin template RingSequenceOps(size_t StaticCapacity = 0)
{
private:
    size_t _head;
    size_t _length;

    pragma(inline, true)
    size_t physicalIndex(size_t logicalIndex) const
        nothrow @safe @nogc
    {
        static if (StaticCapacity != 0)
        {
            assert(logicalIndex < StaticCapacity);

            static if ((StaticCapacity & (StaticCapacity - 1)) == 0)
            {
                return (_head + logicalIndex) &
                    (StaticCapacity - 1);
            }
            else
            {
                size_t index = _head + logicalIndex;
                if (index >= StaticCapacity)
                    index -= StaticCapacity;
                return index;
            }
        }
        else
        {
            assert(capacity != 0);
            assert(logicalIndex < capacity);
            assert(_head < capacity);

            // Preserve the M3.3 overflow-safe runtime formulation exactly.
            const tailRoom = capacity - _head;

            if (logicalIndex < tailRoom)
                return _head + logicalIndex;

            return logicalIndex - tailRoom;
        }
    }

    pragma(inline, true)
    void advanceHead()
        nothrow @safe @nogc
    {
        static if (StaticCapacity != 0)
        {
            ++_head;
            if (_head == StaticCapacity)
                _head = 0;
        }
        else
        {
            assert(capacity != 0);
            assert(_head < capacity);

            ++_head;
            if (_head == capacity)
                _head = 0;
        }
    }

    /**
     * Updates logical state after the current front T lifetime has already
     * ended. Storage/lifetime work remains owned by the consuming family.
     */
    pragma(inline, true)
    void consumeFrontState()
        nothrow @safe @nogc
    {
        assert(_length > 0);

        --_length;

        if (_length == 0)
            _head = 0;
        else
            advanceHead();
    }
}

version (unittest)
{
    private struct Static4
    {
        enum size_t capacity = 4;
        mixin RingSequenceOps!4;
    }

    private struct Static3
    {
        enum size_t capacity = 3;
        mixin RingSequenceOps!3;
    }

    private struct Runtime
    {
        size_t _capacity;

        @property size_t capacity() const
            nothrow @safe @nogc
        {
            return _capacity;
        }

        mixin RingSequenceOps;
    }
}

unittest
{
    Static4 sequence;
    sequence._head = 3;
    sequence._length = 3;

    assert(sequence.physicalIndex(0) == 3);
    assert(sequence.physicalIndex(1) == 0);
    assert(sequence.physicalIndex(2) == 1);

    sequence.consumeFrontState();
    assert(sequence._head == 0);
    assert(sequence._length == 2);
}

unittest
{
    Static3 sequence;
    sequence._head = 2;
    sequence._length = 3;

    assert(sequence.physicalIndex(0) == 2);
    assert(sequence.physicalIndex(1) == 0);
    assert(sequence.physicalIndex(2) == 1);
}

unittest
{
    Runtime sequence;
    sequence._capacity = 5;
    sequence._head = 4;
    sequence._length = 3;

    assert(sequence.physicalIndex(0) == 4);
    assert(sequence.physicalIndex(1) == 0);
    assert(sequence.physicalIndex(2) == 1);

    sequence.consumeFrontState();
    assert(sequence._head == 0);
    assert(sequence._length == 2);
}
