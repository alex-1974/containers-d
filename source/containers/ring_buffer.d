/**
 * Provides a fixed-capacity FIFO ring buffer with inline storage.
 *
 * The primary entry point is $(LREF StaticRingBuffer).
 *
 * The module is not yet re-exported from the package facade while the first
 * admission gate is being completed.
 *
 * See_Also:
 *   `docs/design/ring-buffer-core.md`,
 *   `evidence/performance/ring-buffer-wraparound.md`
 */
module containers.ring_buffer;

import core.lifetime : emplace, forward, moveEmplace;
import std.traits : isCopyable, Unqual;

///
/// Stores up to `Capacity` FIFO elements in inline storage.
///
/// Exactly `length` slots contain live `T` objects. Unused slots are raw
/// storage and are not default-constructed merely because the buffer exists.
///
/// Copy construction is element-wise when `T` is copyable. Whole-buffer move
/// construction is available for element types without a D language move
/// constructor; that temporary restriction is tracked in issue #3. Identity
/// assignment is currently disabled.
///
/// Params:
///   T = element type
///   Capacity = maximum number of live elements; must be greater than zero
///
/// Init:
///   `.init` is a valid empty buffer with no live `T` objects.
///
/// Complexity:
///   Front/back access, indexed access, push, and pop are O(1).
///
/// Allocation:
///   Container bookkeeping and inline storage do not allocate. Operations of
///   `T` itself may allocate.
///
/// Thread_Safety:
///   Instances are not synchronized. External synchronization is required for
///   concurrent mutation or mutation concurrent with reads.
///
/// Validation:
///   See `docs/validation.md` and
///   `evidence/performance/ring-buffer-wraparound.md`.
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

    T* slotPointer(size_t physicalIndex) nothrow @safe @nogc
    {
        assert(physicalIndex < Capacity);

        // _storage is aligned to T.alignof and physicalIndex selects one
        // T-sized slot inside it. The compiler cannot prove that converting
        // this raw byte address to T* preserves alignment; keep only that cast
        // inside the trusted boundary. Callers remain responsible for using the
        // pointer only according to the slot's live-object state.
        return (() @trusted =>
            cast(T*) (_storage.ptr + physicalIndex * T.sizeof))();
    }

    const(T)* slotPointer(size_t physicalIndex) const nothrow @safe @nogc
    {
        assert(physicalIndex < Capacity);

        // Same aligned-slot argument as the mutable overload above.
        return (() @trusted =>
            cast(const(T)*) (_storage.ptr + physicalIndex * T.sizeof))();
    }

    size_t physicalIndex(size_t logicalIndex) const nothrow @safe @nogc
    {
        assert(logicalIndex < Capacity);

        static if ((Capacity & (Capacity - 1)) == 0)
        {
            // Measured specialization: for power-of-two capacities both DMD
            // 2.111 and LDC 1.41 produce fewer retired instructions than the
            // branch/subtract path. See
            // evidence/performance/ring-buffer-wraparound.md.
            return (_head + logicalIndex) & (Capacity - 1);
        }
        else
        {
            // For non-power-of-two capacities, measured faster than modulo on
            // both baseline compilers.
            size_t index = _head + logicalIndex;
            if (index >= Capacity)
                index -= Capacity;
            return index;
        }
    }

    void advanceHead() nothrow @safe @nogc
    {
        ++_head;
        if (_head == Capacity)
            _head = 0;
    }

    // Ends the container's ownership of a front slot whose T lifetime has
    // already ended through move construction. No destructor is called here.
    void consumeMovedFront() nothrow @safe @nogc
    {
        assert(_length > 0);

        --_length;
        if (_length == 0)
        {
            _head = 0;
        }
        else
        {
            advanceHead();
        }
    }

public:
    static if (isCopyable!T)
    {
        /**
         * Element-wise copy construction.
         *
         * The destination is laid out contiguously from physical slot zero even
         * when the source is wrapped. The source remains unchanged.
         *
         * If copying an element fails, already-constructed destination elements
         * are destroyed before the exception leaves the constructor.
         */
        this(ref return scope typeof(this) rhs)
        {
            scope(failure) clear();

            foreach (logicalIndex; 0 .. rhs._length)
            {
                const sourceIndex = rhs.physicalIndex(logicalIndex);
                emplace(slotPointer(_length), *rhs.slotPointer(sourceIndex));
                ++_length;
            }
        }
    }
    else
    {
        /// Copy construction is unavailable when T itself is not copyable.
        @disable this(ref return scope typeof(this) rhs);
    }

    static if (__traits(hasMoveConstructor, T))
    {
        /**
         * Whole-buffer move construction is temporarily unavailable when T
         * defines a language move constructor.
         *
         * DMD 2.111's core.lifetime.moveEmplace implements relocation through
         * blit/opPostMove/wipe semantics and does not dispatch T's language move
         * constructor. Using it here would silently bypass T's contract.
         */
        @disable this(return scope typeof(this) rhs);
    }
    else
    {
        /**
         * Element-wise destructive relocation into uninitialized inline
         * storage using the baseline runtime's moveEmplace contract.
         *
         * Each source slot is wiped by moveEmplace, explicitly destroyed in its
         * moved-from state, and only then removed from the source buffer's live
         * accounting.
         */
        this(return scope typeof(this) rhs)
        {
            scope(failure) clear();

            while (!rhs.empty)
            {
                auto source = rhs.slotPointer(rhs._head);
                auto target = slotPointer(_length);

                moveEmplace(*source, *target);
                destroy!false(*source);

                ++_length;
                rhs.consumeMovedFront();
            }
        }
    }

    // Identity assignment remains deliberately unavailable until its
    // self-assignment and exception guarantees are specified.
    @disable ref typeof(this) opAssign(ref typeof(this) rhs);

    /// Returns the number of live elements.
    size_t length() const nothrow @safe @nogc
    {
        return _length;
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 2) buffer;
        assert(buffer.length == 0);
        assert(buffer.tryPushBack(7));
        assert(buffer.length == 1);
    }

    /// Returns whether the buffer contains no live elements.
    bool empty() const nothrow @safe @nogc
    {
        return _length == 0;
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 1) buffer;
        assert(buffer.empty);
        assert(buffer.tryPushBack(1));
        assert(!buffer.empty);
    }

    /// Returns whether all `Capacity` slots contain live elements.
    bool full() const nothrow @safe @nogc
    {
        return _length == Capacity;
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 1) buffer;
        assert(!buffer.full);
        assert(buffer.tryPushBack(1));
        assert(buffer.full);
    }

    /// Returns a mutable reference to the logical front element.
    ref T front()
    {
        assert(!empty);
        return *slotPointer(_head);
    }

    /// ditto
    ref const(T) front() const
    {
        assert(!empty);
        return *slotPointer(_head);
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 2) buffer;
        assert(buffer.tryPushBack(10));
        assert(buffer.front == 10);
        buffer.front = 11;
        assert(buffer.front == 11);
    }

    /// Returns a mutable reference to the logical back element.
    ref T back()
    {
        assert(!empty);
        return *slotPointer(physicalIndex(_length - 1));
    }

    /// ditto
    ref const(T) back() const
    {
        assert(!empty);
        return *slotPointer(physicalIndex(_length - 1));
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 2) buffer;
        assert(buffer.tryPushBack(10));
        assert(buffer.tryPushBack(20));
        assert(buffer.back == 20);
    }

    /// Returns a mutable reference to an element by logical FIFO index.
    ref T opIndex(size_t logicalIndex)
    {
        assert(logicalIndex < _length);
        return *slotPointer(physicalIndex(logicalIndex));
    }

    /// ditto
    ref const(T) opIndex(size_t logicalIndex) const
    {
        assert(logicalIndex < _length);
        return *slotPointer(physicalIndex(logicalIndex));
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 3) buffer;
        assert(buffer.tryPushBack(10));
        assert(buffer.tryPushBack(20));
        assert(buffer[0] == 10);
        assert(buffer[1] == 20);
    }

    /**
     * Appends one value without overwriting existing elements.
     *
     * Returns false when full. On that path the logical sequence is unchanged
     * and the container performs no allocation or element construction.
     *
     * The argument category is forwarded to T's construction.
     *
     * Returns:
     *   `true` when a new element was constructed; `false` when already full.
     *
     * Failure:
     *   When full, the logical sequence and all existing elements are unchanged.
     *
     * Complexity:
     *   O(1).
     *
     * Allocation:
     *   The container itself does not allocate.
     */
    bool tryPushBack(U)(auto ref U value)
    if (is(Unqual!U == T) &&
        __traits(compiles, emplace(cast(T*) null, forward!value)))
    {
        if (full)
            return false;

        const insertionIndex = physicalIndex(_length);
        emplace(slotPointer(insertionIndex), forward!value);
        ++_length;
        return true;
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 1) buffer;
        assert(buffer.tryPushBack(7));
        assert(!buffer.tryPushBack(8));
        assert(buffer.front == 7);
    }

    /**
     * Removes and destroys the front element.
     *
     * Preconditions:
     *   The buffer is not empty.
     *
     * Complexity:
     *   O(1).
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

    ///
    unittest
    {
        StaticRingBuffer!(int, 2) buffer;
        assert(buffer.tryPushBack(1));
        assert(buffer.tryPushBack(2));
        buffer.popFront();
        assert(buffer.front == 2);
    }

    /**
     * Destroys every live element and leaves the buffer empty.
     *
     * Complexity:
     *   O(length).
     */
    void clear()
    {
        while (!empty)
            popFront();
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 2) buffer;
        assert(buffer.tryPushBack(1));
        assert(buffer.tryPushBack(2));
        buffer.clear();
        assert(buffer.empty);
    }

    ~this()
    {
        clear();
    }

}

///
unittest
{
    StaticRingBuffer!(int, 3) buffer;
    assert(buffer.tryPushBack(10));
    assert(buffer.tryPushBack(20));
    buffer.popFront();
    assert(buffer.front == 20);
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
    alias Buffer = StaticRingBuffer!(int, 4);

    Buffer original;
    assert(original.tryPushBack(10));
    assert(original.tryPushBack(20));
    assert(original.tryPushBack(30));
    assert(original.tryPushBack(40));
    original.popFront();
    original.popFront();
    assert(original.tryPushBack(50));
    assert(original.tryPushBack(60));

    // Copy construction preserves logical order across physical wraparound.
    Buffer copy = original;
    assert(copy.length == 4);
    assert(copy[0] == 30);
    assert(copy[1] == 40);
    assert(copy[2] == 50);
    assert(copy[3] == 60);

    // The copy owns independent element lifetimes/storage.
    original.popFront();
    assert(original.tryPushBack(70));
    assert(copy[0] == 30);
    assert(copy[3] == 60);

    // Identity assignment is still deliberately unavailable.
    static assert(!__traits(compiles, {
        Buffer a;
        Buffer b;
        b = a;
    }));
}

unittest
{
    alias Buffer = StaticRingBuffer!(int, 4);

    Buffer source;
    assert(source.tryPushBack(1));
    assert(source.tryPushBack(2));
    assert(source.tryPushBack(3));
    source.popFront();
    assert(source.tryPushBack(4));
    assert(source.tryPushBack(5));

    // Move construction also normalizes a wrapped source into logical order.
    Buffer moved = __rvalue(source);
    assert(moved.length == 4);
    assert(moved[0] == 2);
    assert(moved[1] == 3);
    assert(moved[2] == 4);
    assert(moved[3] == 5);

    // The D language ends the source lifetime at move construction. Do not
    // inspect or otherwise use source here.
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

    auto address = cast(size_t) &buffer[0];
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

unittest
{
    // A move-only element keeps the buffer move-constructible without making
    // the buffer copy-constructible.
    struct MoveOnly
    {
        int value;

        this(int value)
        {
            this.value = value;
        }

        @disable this(ref return scope MoveOnly rhs);

        this(return scope MoveOnly rhs)
        {
            value = rhs.value;
            rhs.value = -1;
        }
    }

    alias Buffer = StaticRingBuffer!(MoveOnly, 2);

    static assert(!__traits(compiles, {
        Buffer source;
        Buffer copy = source;
    }));

    static assert(__traits(hasMoveConstructor, MoveOnly));

    static assert(!__traits(compiles, {
        Buffer source;
        Buffer moved = __rvalue(source);
    }));
}

unittest
{
    // Whole-buffer copy and move construction must preserve non-trivial element
    // lifetime accounting. A move transfers one live lifetime; it does not
    // create an additional live element.
    struct TrackedTransfer
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

        this(ref return scope TrackedTransfer rhs)
        {
            value = rhs.value;
            ++alive;
            ++copied;
        }

        this(return scope TrackedTransfer rhs)
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

    TrackedTransfer.alive = 0;
    TrackedTransfer.copied = 0;
    TrackedTransfer.moved = 0;
    TrackedTransfer.destroyed = 0;

    {
        auto seed = TrackedTransfer(17);
        assert(TrackedTransfer.alive == 1);

        StaticRingBuffer!(TrackedTransfer, 3) original;
        assert(original.tryPushBack(seed));
        assert(original.tryPushBack(seed));
        assert(original.tryPushBack(seed));

        assert(TrackedTransfer.alive == 4);
        assert(TrackedTransfer.copied == 3);

        StaticRingBuffer!(TrackedTransfer, 3) copy = original;

        assert(copy.length == 3);
        assert(copy[0].value == 17);
        assert(copy[1].value == 17);
        assert(copy[2].value == 17);
        assert(TrackedTransfer.alive == 7);
        assert(TrackedTransfer.copied == 6);

        // T defines a language move constructor, so whole-buffer move remains
        // disabled until the raw-storage implementation can dispatch it
        // correctly on every supported baseline.
        static assert(__traits(hasMoveConstructor, TrackedTransfer));
        static assert(!__traits(compiles, {
            StaticRingBuffer!(TrackedTransfer, 3) moved = __rvalue(copy);
        }));

        original.clear();
        assert(TrackedTransfer.alive == 4);

        copy.clear();
        assert(TrackedTransfer.alive == 1);
        assert(TrackedTransfer.destroyed == 6);
    }

    assert(TrackedTransfer.alive == 0);
    assert(TrackedTransfer.destroyed == 7);
}

unittest
{
    // For a trivial element type, the ordinary steady-state API must be usable
    // from @safe @nogc nothrow code.
    alias Buffer = StaticRingBuffer!(int, 5);

    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
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
    // Deterministic adversarial model test. It repeatedly mixes append, pop,
    // clear and observation while comparing every externally visible sequence
    // property with a deliberately simple non-ring reference model.
    enum size_t modelCapacity = 7;
    alias Buffer = StaticRingBuffer!(int, modelCapacity);

    Buffer buffer;

    int[modelCapacity] model;
    size_t modelLength;

    uint state = 0xC0FF_EE11;

    foreach (step; 0 .. 20_000)
    {
        // xorshift32 with a fixed seed keeps failures reproducible.
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;

        const operation = state % 11;

        if (operation <= 5)
        {
            const value = cast(int) (state ^ cast(uint) step);
            const expectedSuccess = modelLength < modelCapacity;

            assert(buffer.tryPushBack(value) == expectedSuccess);

            if (expectedSuccess)
                model[modelLength++] = value;
        }
        else if (operation <= 8)
        {
            if (modelLength != 0)
            {
                buffer.popFront();

                foreach (i; 1 .. modelLength)
                    model[i - 1] = model[i];

                --modelLength;
            }
        }
        else if (operation == 9)
        {
            buffer.clear();
            modelLength = 0;
        }
        else
        {
            // Observation-only step deliberately leaves both models untouched.
        }

        assert(buffer.length == modelLength);
        assert(buffer.empty == (modelLength == 0));
        assert(buffer.full == (modelLength == modelCapacity));

        foreach (i; 0 .. modelLength)
            assert(buffer[i] == model[i]);

        if (modelLength != 0)
        {
            assert(buffer.front == model[0]);
            assert(buffer.back == model[modelLength - 1]);
        }
    }

    buffer.clear();
    assert(buffer.empty);
}

unittest
{
    // For an element without a language move constructor, baseline
    // moveEmplace relocation must transfer resource ownership without releasing
    // the resource from the wiped source slot.
    struct RelocatableOwner
    {
        static int releases;

        int value;
        bool armed;

        this(int value)
        {
            this.value = value;
            armed = true;
        }

        this(ref return scope RelocatableOwner rhs)
        {
            value = rhs.value;
            armed = rhs.armed;
        }

        ~this()
        {
            if (armed)
                ++releases;
        }
    }

    static assert(!__traits(hasMoveConstructor, RelocatableOwner));

    RelocatableOwner.releases = 0;

    {
        auto seed = RelocatableOwner(41);

        StaticRingBuffer!(RelocatableOwner, 3) source;
        assert(source.tryPushBack(seed));
        assert(source.tryPushBack(seed));
        assert(source.tryPushBack(seed));

        StaticRingBuffer!(RelocatableOwner, 3) moved = __rvalue(source);

        assert(moved.length == 3);
        assert(moved[0].value == 41);
        assert(moved[1].value == 41);
        assert(moved[2].value == 41);

        // Wiped moved-from slots are destroyed with armed == false.
        assert(RelocatableOwner.releases == 0);

        moved.clear();
        assert(RelocatableOwner.releases == 3);
    }

    // The independent seed owns and releases its own copied resource token.
    assert(RelocatableOwner.releases == 4);
}
