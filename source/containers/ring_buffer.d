/**
 * Fixed-capacity ring buffer primitives.
 *
 * This module is not yet exported from the package facade. Its API remains
 * provisional until the admission gate in docs/design/ring-buffer-core.md is
 * satisfied.
 */
module containers.ring_buffer;

import core.lifetime : emplace, forward;

///
/// Bounded single-threaded FIFO ring buffer with inline storage.
///
/// Exactly `length` slots contain live `T` objects. Unused slots are raw
/// storage and are not default-constructed merely because the buffer exists.
///
/// Copying, moving, and identity assignment of the whole buffer are disabled
/// during the semantic-core milestone. This prevents accidental bitwise
/// relocation of live elements in raw storage until explicit element-wise
/// semantics are implemented and validated.
///
/// Params:
///   T = element type
///   Capacity = maximum number of live elements; must be greater than zero
///
struct StaticRingBuffer(T, size_t Capacity)
{
    static assert(Capacity > 0,
        "StaticRingBuffer capacity must be greater than zero");
    static assert(T.sizeof > 0,
        "StaticRingBuffer requires an element type with non-zero size");

    /// Compile-time maximum number of live elements.
    enum size_t capacity = Capacity;

private:
    // One aligned byte region owns storage for Capacity potential T objects.
    // Bytes are intentionally left uninitialized until an element lifetime
    // begins through emplace.
    align(T.alignof) ubyte[T.sizeof * Capacity] _storage = void;

    size_t _head;
    size_t _length;

    @trusted T* slotPointer(size_t physicalIndex) nothrow @nogc
    {
        assert(physicalIndex < Capacity);
        return cast(T*) (_storage.ptr + physicalIndex * T.sizeof);
    }

    @trusted const(T)* slotPointer(size_t physicalIndex) const nothrow @nogc
    {
        assert(physicalIndex < Capacity);
        return cast(const(T)*) (_storage.ptr + physicalIndex * T.sizeof);
    }

    size_t physicalIndex(size_t logicalIndex) const nothrow @safe @nogc
    {
        assert(logicalIndex < Capacity);

        size_t index = _head + logicalIndex;
        if (index >= Capacity)
            index -= Capacity;
        return index;
    }

    void advanceHead() nothrow @safe @nogc
    {
        ++_head;
        if (_head == Capacity)
            _head = 0;
    }

public:
    // Raw inline storage cannot yet be copied or moved as a whole safely for
    // arbitrary non-trivial T. Keep these operations impossible until explicit
    // element-wise semantics are implemented.
    @disable this(ref return scope typeof(this) rhs);
    @disable this(return scope typeof(this) rhs);
    @disable ref typeof(this) opAssign(ref typeof(this) rhs);

    /// Number of live elements.
    size_t length() const nothrow @safe @nogc
    {
        return _length;
    }

    /// Whether no live elements are stored.
    bool empty() const nothrow @safe @nogc
    {
        return _length == 0;
    }

    /// Whether all slots contain live elements.
    bool full() const nothrow @safe @nogc
    {
        return _length == Capacity;
    }

    /// Front element.
    ref T front()
    {
        assert(!empty);
        return *slotPointer(_head);
    }

    /// Front element, const overload.
    ref const(T) front() const
    {
        assert(!empty);
        return *slotPointer(_head);
    }

    /// Back element.
    ref T back()
    {
        assert(!empty);
        return *slotPointer(physicalIndex(_length - 1));
    }

    /// Back element, const overload.
    ref const(T) back() const
    {
        assert(!empty);
        return *slotPointer(physicalIndex(_length - 1));
    }

    /// Logical indexed access independent of physical wraparound.
    ref T opIndex(size_t logicalIndex)
    {
        assert(logicalIndex < _length);
        return *slotPointer(physicalIndex(logicalIndex));
    }

    /// Logical indexed access, const overload.
    ref const(T) opIndex(size_t logicalIndex) const
    {
        assert(logicalIndex < _length);
        return *slotPointer(physicalIndex(logicalIndex));
    }

    /**
     * Appends one value without overwriting existing elements.
     *
     * Returns false when full. On that path the logical sequence is unchanged
     * and the container performs no allocation or element construction.
     *
     * The argument category is forwarded to T's construction.
     */
    bool tryPushBack(U)(auto ref U value)
    if (is(U == T))
    {
        if (full)
            return false;

        const insertionIndex = physicalIndex(_length);
        emplace(slotPointer(insertionIndex), forward!value);
        ++_length;
        return true;
    }

    /**
     * Removes and destroys the front element.
     *
     * Precondition: the buffer is not empty.
     */
    void popFront()
    {
        assert(!empty);

        destroy!false(*slotPointer(_head));

        --_length;
        if (_length == 0)
        {
            // Canonical empty representation keeps subsequent first insertion
            // at physical slot zero.
            _head = 0;
        }
        else
        {
            advanceHead();
        }
    }

    /// Destroys every live element and leaves the buffer empty.
    void clear()
    {
        while (!empty)
            popFront();
    }

    ~this()
    {
        clear();
    }
}

unittest
{
    alias Buffer = StaticRingBuffer!(int, 4);

    Buffer buffer;
    assert(buffer.capacity == 4);
    assert(buffer.length == 0);
    assert(buffer.empty);
    assert(!buffer.full);

    assert(buffer.tryPushBack(10));
    assert(buffer.tryPushBack(20));
    assert(buffer.tryPushBack(30));
    assert(buffer.tryPushBack(40));

    assert(buffer.full);
    assert(buffer.length == 4);
    assert(buffer.front == 10);
    assert(buffer.back == 40);
    assert(buffer[0] == 10);
    assert(buffer[1] == 20);
    assert(buffer[2] == 30);
    assert(buffer[3] == 40);

    // Full insertion is non-overwriting and leaves the sequence unchanged.
    assert(!buffer.tryPushBack(50));
    assert(buffer.length == 4);
    assert(buffer.front == 10);
    assert(buffer.back == 40);

    buffer.popFront();
    buffer.popFront();

    assert(buffer.tryPushBack(50));
    assert(buffer.tryPushBack(60));

    // Logical order crosses the physical wrap boundary.
    assert(buffer.length == 4);
    assert(buffer[0] == 30);
    assert(buffer[1] == 40);
    assert(buffer[2] == 50);
    assert(buffer[3] == 60);

    buffer.clear();
    assert(buffer.empty);
    assert(buffer.length == 0);

    // Canonical empty state remains reusable.
    assert(buffer.tryPushBack(70));
    assert(buffer.front == 70);
    assert(buffer.back == 70);
}

unittest
{
    // Capacity one exercises empty/full disambiguation without reserving a
    // sentinel slot.
    StaticRingBuffer!(int, 1) buffer;

    assert(buffer.empty);
    assert(buffer.tryPushBack(1));
    assert(buffer.full);
    assert(!buffer.tryPushBack(2));
    assert(buffer.front == 1);

    buffer.popFront();
    assert(buffer.empty);

    assert(buffer.tryPushBack(3));
    assert(buffer.front == 3);
}

unittest
{
    // The initial implementation deliberately rejects whole-buffer bit copies
    // and moves until element-wise semantics are implemented.
    alias Buffer = StaticRingBuffer!(int, 2);

    static assert(!__traits(compiles, {
        Buffer a;
        Buffer b = a;
    }));

    static assert(!__traits(compiles, {
        Buffer a;
        Buffer b = __rvalue(a);
    }));

    static assert(!__traits(compiles, {
        Buffer a;
        Buffer b;
        b = a;
    }));
}

unittest
{
    // Public ordinary operations must remain usable from @safe code for a safe
    // element type.
    alias Buffer = StaticRingBuffer!(int, 3);

    static assert(__traits(compiles, {
        () @safe {
            Buffer buffer;
            assert(buffer.tryPushBack(1));
            assert(buffer.tryPushBack(2));
            assert(buffer.front == 1);
            assert(buffer.back == 2);
            assert(buffer[1] == 2);
            buffer.popFront();
            buffer.clear();
        }();
    }));
}

unittest
{
    // Live objects must respect T.alignof even though the backing region is raw
    // bytes.
    align(32) struct OverAligned
    {
        long value;
    }

    StaticRingBuffer!(OverAligned, 3) buffer;
    OverAligned value;
    value.value = 42;

    assert(buffer.tryPushBack(value));

    auto address = cast(size_t) &buffer.front;
    assert(address % OverAligned.alignof == 0);
}

unittest
{
    // Non-trivial element lifetime: only live slots own objects, removal
    // destroys exactly one buffer-owned element, and clear destroys the rest.
    struct Tracked
    {
        static int alive;
        static int copied;
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
            ++copied;
        }

        ~this()
        {
            --alive;
            ++destroyed;
        }
    }

    Tracked.alive = 0;
    Tracked.copied = 0;
    Tracked.destroyed = 0;

    {
        auto source = Tracked(7);
        assert(Tracked.alive == 1);

        {
            StaticRingBuffer!(Tracked, 2) buffer;

            assert(buffer.tryPushBack(source));
            assert(buffer.tryPushBack(source));

            assert(buffer.length == 2);
            assert(Tracked.alive == 3);
            assert(Tracked.copied == 2);

            buffer.popFront();
            assert(buffer.length == 1);
            assert(Tracked.alive == 2);
            assert(Tracked.destroyed == 1);

            buffer.clear();
            assert(buffer.empty);
            assert(Tracked.alive == 1);
            assert(Tracked.destroyed == 2);
        }

        // The cleared buffer has no remaining live T to destroy.
        assert(Tracked.alive == 1);
        assert(Tracked.destroyed == 2);
    }

    assert(Tracked.alive == 0);
    assert(Tracked.destroyed == 3);
}
