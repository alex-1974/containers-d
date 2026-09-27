/**
 * Runtime-capacity owning FIFO ring buffer.
 *
 * This module is provisional during the M3.2 implementation gate. RingBuffer
 * is package-visible only and is not yet re-exported from the package root.
 */
module containers.runtime_ring_buffer;

import containers.internal.runtime_storage : RuntimeStorageOwner;
import core.lifetime : emplace, forward;
import std.traits : Unqual;

/**
 * Owning bounded FIFO ring buffer with runtime-selected capacity.
 *
 * The backing storage is acquired once at construction and retained across
 * push/pop/clear operations. Exactly length slots contain live T objects.
 *
 * This type remains package-visible until its public admission gate is
 * complete.
 */
package(containers) struct RingBuffer(T)
{
    static assert(T.sizeof > 0,
        "RingBuffer requires an element type with non-zero size");

private:
    RuntimeStorageOwner!T _storage;
    size_t _head;
    size_t _length;

    size_t physicalIndex(size_t logicalIndex) const @safe @nogc nothrow
    {
        assert(logicalIndex < capacity);
        assert(capacity != 0);
        assert(_head < capacity);

        // Overflow-safe for every representable runtime capacity. M3.3 will
        // benchmark alternative runtime wraparound shapes before specializing.
        const tailRoom = capacity - _head;

        if (logicalIndex < tailRoom)
            return _head + logicalIndex;

        return logicalIndex - tailRoom;
    }

    void advanceHead() @safe @nogc nothrow
    {
        assert(capacity != 0);
        assert(_head < capacity);

        ++_head;
        if (_head == capacity)
            _head = 0;
    }

public:
    /**
     * Acquires backing storage for capacity elements.
     *
     * Capacity zero is valid and produces the same observable inert state as
     * .init.
     */
    this(size_t capacity) @safe @nogc nothrow
    {
        _storage.initialize(capacity);
    }

    /// Unique owning storage is never copied implicitly.
    @disable this(ref return scope typeof(this) rhs);

    /**
     * Transfers backing-storage ownership in O(1).
     *
     * Element addresses do not change and no T copy/move constructor runs.
     * The source becomes the inert .init-equivalent state.
     */
    this(return scope typeof(this) rhs) @safe @nogc nothrow
    {
        _storage.takeOwnershipFrom(rhs._storage);
        _head = rhs._head;
        _length = rhs._length;

        rhs._head = 0;
        rhs._length = 0;
    }

    /// Identity assignment remains unavailable in the first owning API.
    @disable ref typeof(this) opAssign(ref typeof(this) rhs);

    ~this()
    {
        clear();
    }

    /// Maximum number of live elements.
    size_t capacity() const @safe @nogc nothrow
    {
        return _storage.capacity;
    }

    /// Number of live elements.
    size_t length() const @safe @nogc nothrow
    {
        return _length;
    }

    /// Whether no live elements are stored.
    bool empty() const @safe @nogc nothrow
    {
        return _length == 0;
    }

    /// Whether no additional element can be inserted.
    bool full() const @safe @nogc nothrow
    {
        return _length == capacity;
    }

    /// Mutable logical front element.
    ref T front() return scope
    {
        assert(!empty);
        return *_storage.slotPointer(_head);
    }

    /// ditto
    ref const(T) front() const return scope
    {
        assert(!empty);
        return *_storage.slotPointer(_head);
    }

    /// Mutable logical back element.
    ref T back() return scope
    {
        assert(!empty);
        return *_storage.slotPointer(physicalIndex(_length - 1));
    }

    /// ditto
    ref const(T) back() const return scope
    {
        assert(!empty);
        return *_storage.slotPointer(physicalIndex(_length - 1));
    }

    /// Mutable logical indexed access independent of physical wraparound.
    ref T opIndex(size_t logicalIndex) return scope
    {
        assert(logicalIndex < _length);
        return *_storage.slotPointer(physicalIndex(logicalIndex));
    }

    /// ditto
    ref const(T) opIndex(size_t logicalIndex) const return scope
    {
        assert(logicalIndex < _length);
        return *_storage.slotPointer(physicalIndex(logicalIndex));
    }

    /**
     * Appends one element without overwriting existing contents.
     *
     * Returns false when full. A failed insertion leaves the logical sequence
     * unchanged.
     */
    bool tryPushBack(U)(auto ref U value)
    if (is(Unqual!U == T) &&
        __traits(compiles, emplace(cast(T*) null, forward!value)))
    {
        if (full)
            return false;

        const physical = physicalIndex(_length);
        emplace(_storage.slotPointer(physical), forward!value);
        ++_length;
        return true;
    }

    /**
     * Destroys and removes the logical front element.
     *
     * Precondition: the buffer is not empty.
     */
    void popFront()
    {
        assert(!empty);

        const physical = _head;
        destroy!false(*_storage.slotPointer(physical));
        _storage.clearVacatedSlot(physical);

        --_length;

        if (_length == 0)
            _head = 0;
        else
            advanceHead();
    }

    /**
     * Destroys all live elements while retaining the backing allocation.
     */
    void clear()
    {
        while (!empty)
            popFront();
    }
}

version (unittest)
{
    private struct RuntimeTracked
    {
        static int alive;
        static int copied;
        static int moved;
        static int destroyed;

        int value;

        this(int value)
        {
            this.value = value;
            ++alive;
        }

        this(ref return scope RuntimeTracked rhs)
        {
            value = rhs.value;
            ++alive;
            ++copied;
        }

        this(return scope RuntimeTracked rhs)
        {
            value = rhs.value;
            rhs.value = -1;
            ++alive;
            ++moved;
        }

        ~this()
        {
            --alive;
            ++destroyed;
        }
    }
}

unittest
{
    RingBuffer!int initial;
    assert(initial.capacity == 0);
    assert(initial.length == 0);
    assert(initial.empty);
    assert(initial.full);
    assert(!initial.tryPushBack(1));

    auto zero = RingBuffer!int(0);
    assert(zero.capacity == 0);
    assert(zero.length == 0);
    assert(zero.empty);
    assert(zero.full);
    assert(!zero.tryPushBack(1));
}

unittest
{
    auto buffer = RingBuffer!int(4);

    assert(buffer.capacity == 4);
    assert(buffer.empty);
    assert(!buffer.full);

    assert(buffer.tryPushBack(10));
    assert(buffer.tryPushBack(20));
    assert(buffer.tryPushBack(30));
    assert(buffer.tryPushBack(40));

    assert(buffer.full);
    assert(!buffer.tryPushBack(50));
    assert(buffer.length == 4);
    assert(buffer.front == 10);
    assert(buffer.back == 40);

    buffer.popFront();
    buffer.popFront();

    assert(buffer.front == 30);
    assert(buffer.tryPushBack(50));
    assert(buffer.tryPushBack(60));

    assert(buffer.length == 4);
    assert(buffer[0] == 30);
    assert(buffer[1] == 40);
    assert(buffer[2] == 50);
    assert(buffer[3] == 60);
    assert(buffer.back == 60);

    buffer.clear();
    assert(buffer.empty);
    assert(buffer.capacity == 4);

    assert(buffer.tryPushBack(70));
    assert(buffer.front == 70);
}

unittest
{
    auto buffer = RingBuffer!int(1);

    assert(buffer.tryPushBack(7));
    assert(buffer.full);
    assert(!buffer.tryPushBack(8));
    assert(buffer.front == 7);

    buffer.popFront();
    assert(buffer.empty);
    assert(buffer.capacity == 1);

    assert(buffer.tryPushBack(9));
    assert(buffer.front == 9);
}

unittest
{
    alias Buffer = RingBuffer!int;

    static assert(!__traits(compiles, {
        Buffer source;
        Buffer copy = source;
    }));

    static assert(!__traits(compiles, {
        Buffer source;
        Buffer target;
        target = source;
    }));
}

unittest
{
    // Whole-buffer move transfers only storage ownership. Elements stay at the
    // same addresses, so no T copy/move construction occurs.
    RuntimeTracked.alive = 0;
    RuntimeTracked.copied = 0;
    RuntimeTracked.moved = 0;
    RuntimeTracked.destroyed = 0;

    {
        auto seed = RuntimeTracked(11);
        auto source = RingBuffer!RuntimeTracked(3);

        assert(source.tryPushBack(seed));
        assert(source.tryPushBack(seed));
        assert(source.tryPushBack(seed));

        const copiedBefore = RuntimeTracked.copied;
        const movedBefore = RuntimeTracked.moved;

        auto moved = __rvalue(source);

        assert(source.capacity == 0);
        assert(source.length == 0);
        assert(source.empty);
        assert(source.full);

        assert(moved.capacity == 3);
        assert(moved.length == 3);
        assert(moved[0].value == 11);
        assert(moved[1].value == 11);
        assert(moved[2].value == 11);

        assert(RuntimeTracked.copied == copiedBefore);
        assert(RuntimeTracked.moved == movedBefore);
    }

    assert(RuntimeTracked.alive == 0);
}

unittest
{
    // Deterministic adversarial comparison against a simple linear model.
    enum size_t capacity = 7;
    enum size_t steps = 20_000;

    auto buffer = RingBuffer!int(capacity);
    int[capacity] model = void;
    size_t modelLength;

    uint state = 0xA11C_E551;

    foreach (step; 0 .. steps)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;

        const operation = state % 5;

        final switch (operation)
        {
            case 0:
            case 1:
            {
                const value = cast(int) (state ^ cast(uint) step);
                const accepted = buffer.tryPushBack(value);

                if (modelLength == capacity)
                {
                    assert(!accepted);
                }
                else
                {
                    assert(accepted);
                    model[modelLength++] = value;
                }
                break;
            }

            case 2:
            {
                if (modelLength != 0)
                {
                    buffer.popFront();

                    foreach (i; 1 .. modelLength)
                        model[i - 1] = model[i];

                    --modelLength;
                }
                break;
            }

            case 3:
            {
                if ((state & 0x3F) == 0)
                {
                    buffer.clear();
                    modelLength = 0;
                }
                break;
            }

            case 4:
                break;
        }

        assert(buffer.capacity == capacity);
        assert(buffer.length == modelLength);
        assert(buffer.empty == (modelLength == 0));
        assert(buffer.full == (modelLength == capacity));

        foreach (i; 0 .. modelLength)
            assert(buffer[i] == model[i]);

        if (modelLength != 0)
        {
            assert(buffer.front == model[0]);
            assert(buffer.back == model[modelLength - 1]);
        }
    }
}

unittest
{
    // Trivial-element steady-state and owner move are usable from
    // @safe @nogc nothrow code.
    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
            auto source = RingBuffer!int(5);

            assert(source.tryPushBack(1));
            assert(source.tryPushBack(2));
            source.popFront();

            auto moved = __rvalue(source);
            assert(moved.front == 2);
            moved.clear();
        }();
    }));
}
