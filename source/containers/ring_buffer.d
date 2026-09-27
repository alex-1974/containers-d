/**
 * Provides a fixed-capacity FIFO ring buffer with inline storage.
 *
 * The primary entry point is $(LREF StaticRingBuffer), also re-exported from
 * the package root `containers`.
 *
 * See_Also:
 *   `docs/design/ring-buffer-core.md`,
 *   `evidence/performance/ring-buffer-wraparound.md`
 */
module containers.ring_buffer;

import core.lifetime : emplace, forward, moveEmplace;
import std.traits : hasElaborateDestructor, hasIndirections, isCopyable, isNested, Unqual;

private union StaticRingStorage(T, size_t Capacity)
{
    static if (hasIndirections!T)
    {
        static if (isNested!T)
        {
            // Embedding a nested T would make this storage aggregate inherit
            // T's hidden context pointer. Use a conservative scan shape instead
            // while issue #10 researches nested-element semantics separately.
            void[T.sizeof * Capacity] conservativeGcShape;
        }
        else
        {
            // For ordinary element types, expose T's exact repeated pointer
            // layout to the compiler-generated GC bitmap.
            T[Capacity] gcShape;
        }
    }

    align(T.alignof) ubyte[T.sizeof * Capacity] bytes;
}

version (unittest)
{
    private struct MoveOnlyTestElement
    {
        int value;

        this(int value)
        {
            this.value = value;
        }

        @disable this(ref return scope MoveOnlyTestElement rhs);

        this(return scope MoveOnlyTestElement rhs)
        {
            value = rhs.value;
            rhs.value = -1;
        }
    }

    private struct TrackedTransferTestElement
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

        this(ref return scope TrackedTransferTestElement rhs)
        {
            value = rhs.value;
            ++alive;
            ++copied;
        }

        this(return scope TrackedTransferTestElement rhs)
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

    private struct SelfReferentialTestElement
    {
        static int moves;

        int value;
        int* self;

        this(int value)
        {
            this.value = value;
            self = &this.value;
        }

        this(ref return scope SelfReferentialTestElement rhs)
        {
            value = rhs.value;
            self = &this.value;
        }

        this(return scope SelfReferentialTestElement rhs) @system nothrow @nogc
        {
            value = rhs.value;
            self = &this.value;
            rhs.value = -1;
            rhs.self = null;
            ++moves;
        }

        bool selfValid() @safe nothrow @nogc
        {
            return self is &value;
        }
    }

    private struct SafeMoveTestElement
    {
        int value;

        this(ref return scope SafeMoveTestElement rhs) @safe nothrow @nogc
        {
            value = rhs.value;
        }

        this(return scope SafeMoveTestElement rhs) @safe nothrow @nogc
        {
            value = rhs.value;
            rhs.value = -1;
        }
    }
}

///
/// Stores up to `Capacity` FIFO elements in inline storage.
///
/// Exactly `length` slots contain live `T` objects. Unused slots are raw
/// storage and are not default-constructed merely because the buffer exists.
///
/// Copy construction is element-wise when `T` is copyable. Whole-buffer move
/// construction preserves either T's D language move-constructor contract or,
/// for classic relocation types, the `moveEmplace`/`opPostMove` contract.
/// Identity assignment is currently disabled.
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
    // The raw bytes are the only storage member used by container logic.
    //
    // For indirection-bearing T, StaticRingStorage overlays T[Capacity] only so
    // D's compiler-generated GC pointer bitmap describes the true potential
    // pointer offsets. The union itself owns no T lifetime.
    alias Storage = StaticRingStorage!(T, Capacity);

    static if (hasIndirections!T)
    {
        // Pointer-bearing raw storage must start from a GC-safe .init bitmap
        // rather than arbitrary bytes that could look like stale roots.
        Storage _storage = Storage.init;
    }
    else
    {
        // Pointer-free elements keep the original uninitialized-storage fast
        // path: no byte is read before a T lifetime is explicitly begun.
        Storage _storage = void;
    }

    size_t _head;
    size_t _length;

    T* slotPointer(size_t physicalIndex) scope return nothrow @safe @nogc
    {
        assert(physicalIndex < Capacity);

        // _storage is aligned to T.alignof and physicalIndex selects one
        // T-sized slot inside it. The compiler cannot prove that converting
        // this raw byte address to T* preserves alignment; keep only that cast
        // inside the trusted boundary. Callers remain responsible for using the
        // pointer only according to the slot's live-object state.
        return (() @trusted =>
            cast(T*) (_storage.bytes.ptr + physicalIndex * T.sizeof))();
    }

    const(T)* slotPointer(size_t physicalIndex) const scope return nothrow @safe @nogc
    {
        assert(physicalIndex < Capacity);

        // Same aligned-slot argument as the mutable overload above.
        return (() @trusted =>
            cast(const(T)*) (_storage.bytes.ptr + physicalIndex * T.sizeof))();
    }

    T[] slotSlice(
        size_t physicalStart,
        size_t count) scope return nothrow @safe @nogc
    {
        if (count == 0)
            return null;

        assert(physicalStart < Capacity);
        assert(count <= Capacity - physicalStart);

        // Pointer slicing is the single operation the compiler cannot prove
        // safe here. slotPointer has already established the aligned slot
        // address; count is bounded to the same inline storage region.
        return (() @trusted =>
            slotPointer(physicalStart)[0 .. count])();
    }

    const(T)[] slotSlice(
        size_t physicalStart,
        size_t count) const scope return nothrow @safe @nogc
    {
        if (count == 0)
            return null;

        assert(physicalStart < Capacity);
        assert(count <= Capacity - physicalStart);

        return (() @trusted =>
            slotPointer(physicalStart)[0 .. count])();
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

    // Check whether ordinary language move construction of T is permitted
    // from @safe code. Placement new itself is @system, so the raw-storage
    // helper below may only elevate that operation to @trusted when T's
    // constructor contract is independently @safe.
    enum bool safeLanguageMove = __traits(compiles, {
        void probe(ref T source) @safe
        {
            T target = __rvalue(source);
        }
    });

    static if (__traits(hasMoveConstructor, T))
    {
        static if (safeLanguageMove)
        {
            T* placementMoveConstruct(
                T* target,
                ref T source) @trusted
            {
                // Safety proof:
                // - target comes from slotPointer and is aligned storage for T;
                // - the caller only supplies an unused destination slot;
                // - source is a distinct live T;
                // - T's language move construction is independently @safe;
                // - placement new begins exactly one T lifetime at target.
                return new (*target) T(__rvalue(source));
            }
        }
        else
        {
            T* placementMoveConstruct(
                T* target,
                ref T source) @system
            {
                return new (*target) T(__rvalue(source));
            }
        }
    }

    void clearVacatedSlot(size_t physicalIndex) nothrow @safe @nogc
    {
        static if (hasIndirections!T)
        {
            const begin = physicalIndex * T.sizeof;
            _storage.bytes[begin .. begin + T.sizeof] = 0;
        }
    }

    void endSlotLifetime(size_t physicalIndex)
    {
        static if (hasElaborateDestructor!T)
            destroy!false(*slotPointer(physicalIndex));

        // Class/interface references and other non-struct indirections are
        // values stored in the slot; removing them must not finalize the
        // referenced object. Zeroing only removes the stale GC root.
        clearVacatedSlot(physicalIndex);
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

    /**
     * Element-wise whole-buffer move construction.
     *
     * Types with a D language move constructor are constructed directly at the
     * final destination slot through placement new and `__rvalue`, preserving
     * the element's move-constructor invariants.
     *
     * Other types retain the classic `moveEmplace` relocation path so that
     * `opPostMove` remains effective for self-referential relocatable types.
     */
    this(return scope typeof(this) rhs)
    {
        scope(failure) clear();

        while (!rhs.empty)
        {
            auto source = rhs.slotPointer(rhs._head);
            auto target = slotPointer(_length);

            static if (__traits(hasMoveConstructor, T))
                placementMoveConstruct(target, *source);
            else
                moveEmplace(*source, *target);

            rhs.endSlotLifetime(rhs._head);

            ++_length;
            rhs.consumeMovedFront();
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

    /// Returns whether the buffer contains no live elements.
    bool empty() const nothrow @safe @nogc
    {
        return _length == 0;
    }

    /// Returns whether all `Capacity` slots contain live elements.
    bool full() const nothrow @safe @nogc
    {
        return _length == Capacity;
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

    /**
     * Returns the first contiguous physical segment in logical FIFO order.
     *
     * The returned slice borrows this buffer's inline storage. Successful
     * structural mutation invalidates previously returned segment slices.
     *
     * Returns:
     *   The whole logical sequence when physically contiguous, the tail-side
     *   portion when wrapped, or an empty slice when the buffer is empty.
     *
     * Complexity:
     *   O(1).
     *
     * Allocation:
     *   None.
     */
    T[] firstSegment() scope return nothrow @trusted @nogc
    {
        if (empty)
            return null;

        const physicalRemaining = Capacity - _head;
        const count = _length < physicalRemaining
            ? _length
            : physicalRemaining;

        return slotSlice(_head, count);
    }

    /// ditto
    const(T)[] firstSegment() const scope return nothrow @trusted @nogc
    {
        if (empty)
            return null;

        const physicalRemaining = Capacity - _head;
        const count = _length < physicalRemaining
            ? _length
            : physicalRemaining;

        return slotSlice(_head, count);
    }

    /**
     * Returns the wrapped continuation after $(LREF firstSegment).
     *
     * The returned slice borrows this buffer's inline storage and is empty
     * whenever the logical sequence is physically contiguous.
     *
     * Complexity:
     *   O(1).
     *
     * Allocation:
     *   None.
     */
    T[] secondSegment() scope return nothrow @trusted @nogc
    {
        if (empty)
            return null;

        const firstCount = firstSegment.length;
        const secondCount = _length - firstCount;
        return slotSlice(0, secondCount);
    }

    /// ditto
    const(T)[] secondSegment() const scope return nothrow @trusted @nogc
    {
        if (empty)
            return null;

        const firstCount = firstSegment.length;
        const secondCount = _length - firstCount;
        return slotSlice(0, secondCount);
    }

    ///
    unittest
    {
        StaticRingBuffer!(int, 4) buffer;
        assert(buffer.tryPushBack(10));
        assert(buffer.tryPushBack(20));
        assert(buffer.tryPushBack(30));
        buffer.popFront();
        buffer.popFront();
        assert(buffer.tryPushBack(40));
        assert(buffer.tryPushBack(50));
        assert(buffer.tryPushBack(60));

        assert(buffer.firstSegment == [30, 40]);
        assert(buffer.secondSegment == [50, 60]);

        buffer.secondSegment[0] = 51;
        assert(buffer[2] == 51);
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

        const physical = _head;
        endSlotLifetime(physical);

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
    // Because no structural mutation occurs, existing segment views remain
    // valid across the failed operation.
    auto fullFirst = buffer.firstSegment;
    auto fullSecond = buffer.secondSegment;

    assert(!buffer.tryPushBack(50));
    assert(buffer.length == 4);
    assert(buffer.front == 10);
    assert(buffer.back == 40);
    assert(fullFirst == [10, 20, 30, 40]);
    assert(fullSecond.length == 0);

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
    alias MoveOnly = MoveOnlyTestElement;
    alias Buffer = StaticRingBuffer!(MoveOnly, 2);

    static assert(!__traits(compiles, {
        Buffer source;
        Buffer copy = source;
    }));

    static assert(__traits(hasMoveConstructor, MoveOnly));

    static assert(__traits(compiles, {
        Buffer source;
        Buffer moved = __rvalue(source);
    }));
}
unittest
{
    // Whole-buffer copy and move construction must preserve non-trivial element
    // lifetime accounting. A move transfers one live lifetime; it does not
    // create an additional live element.
    alias TrackedTransfer = TrackedTransferTestElement;

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

        static assert(__traits(hasMoveConstructor, TrackedTransfer));

        // Do not use alive/destruction totals to specify the language's
        // by-value move-parameter destruction details. The observable container
        // contract is that the move constructor is invoked for each element and
        // the destination preserves logical values.
        const movedBefore = TrackedTransfer.moved;
        StaticRingBuffer!(TrackedTransfer, 3) moved = __rvalue(copy);

        assert(moved.length == 3);
        assert(moved[0].value == 17);
        assert(moved[1].value == 17);
        assert(moved[2].value == 17);
        assert(TrackedTransfer.moved == movedBefore + 3);

        original.clear();
        moved.clear();
    }
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

        const first = buffer.firstSegment;
        const second = buffer.secondSegment;

        assert(first.length + second.length == modelLength);

        size_t segmentIndex;
        foreach (value; first)
            assert(value == model[segmentIndex++]);
        foreach (value; second)
            assert(value == model[segmentIndex++]);
        assert(segmentIndex == modelLength);

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

unittest
{
    // Empty and capacity-one segment laws.
    StaticRingBuffer!(int, 1) buffer;

    assert(buffer.firstSegment.length == 0);
    assert(buffer.secondSegment.length == 0);

    assert(buffer.tryPushBack(7));
    assert(buffer.firstSegment == [7]);
    assert(buffer.secondSegment.length == 0);

    buffer.popFront();
    assert(buffer.firstSegment.length == 0);
    assert(buffer.secondSegment.length == 0);
}

unittest
{
    // Full buffer at head zero is one physical segment; after one pop/push it is
    // full with a non-zero head and therefore splits into two FIFO segments.
    StaticRingBuffer!(int, 4) buffer;

    foreach (value; 1 .. 5)
        assert(buffer.tryPushBack(value));

    assert(buffer.firstSegment == [1, 2, 3, 4]);
    assert(buffer.secondSegment.length == 0);

    buffer.popFront();
    assert(buffer.tryPushBack(5));

    assert(buffer.firstSegment == [2, 3, 4]);
    assert(buffer.secondSegment == [5]);

    size_t logicalIndex;
    foreach (value; buffer.firstSegment)
        assert(value == buffer[logicalIndex++]);
    foreach (value; buffer.secondSegment)
        assert(value == buffer[logicalIndex++]);
    assert(logicalIndex == buffer.length);
}

unittest
{
    // Const access preserves the same segmentation and element qualification.
    StaticRingBuffer!(int, 4) mutableBuffer;
    assert(mutableBuffer.tryPushBack(1));
    assert(mutableBuffer.tryPushBack(2));
    mutableBuffer.popFront();
    assert(mutableBuffer.tryPushBack(3));
    assert(mutableBuffer.tryPushBack(4));
    assert(mutableBuffer.tryPushBack(5));

    const buffer = mutableBuffer;
    const(int)[] first = buffer.firstSegment;
    const(int)[] second = buffer.secondSegment;

    assert(first.length + second.length == buffer.length);

    // Copy construction normalizes logical order into physical slot zero, so
    // the const copy is intentionally contiguous even though the source was
    // wrapped.
    assert(first == [2, 3, 4, 5]);
    assert(second.length == 0);
}

unittest
{
    // The segment API itself is allocation-free and callable from ordinary
    // @safe @nogc nothrow code for a trivial element type.
    alias Buffer = StaticRingBuffer!(int, 8);

    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
            Buffer buffer;
            assert(buffer.tryPushBack(1));
            auto first = buffer.firstSegment;
            auto second = buffer.secondSegment;
            assert(first.length + second.length == buffer.length);
        }();
    }));
}

unittest
{
    // A language move constructor must run at the final inline-storage address.
    // Bit relocation would leave self pointing into the source buffer.
    alias SelfReferential = SelfReferentialTestElement;

    static assert(__traits(hasMoveConstructor, SelfReferential));

    SelfReferential.moves = 0;

    auto seed = SelfReferential(61);

    StaticRingBuffer!(SelfReferential, 3) source;
    assert(source.tryPushBack(seed));
    assert(source.tryPushBack(seed));
    assert(source.tryPushBack(seed));

    auto moved = __rvalue(source);

    assert(moved.length == 3);
    assert(SelfReferential.moves == 3);

    foreach (i; 0 .. moved.length)
    {
        assert(moved[i].value == 61);
        assert(moved[i].selfValid);
    }
}

unittest
{
    // Safe element move construction must not make the container move operation
    // spuriously @system merely because placement new is the raw-storage
    // primitive used internally.
    alias SafeMove = SafeMoveTestElement;

    alias Buffer = StaticRingBuffer!(SafeMove, 2);

    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
            Buffer source;
            Buffer moved = __rvalue(source);
        }();
    }));
}

unittest
{
    // Removing a stored class reference ends only the reference value's slot
    // lifetime. It must not explicitly finalize the referenced GC object.
    class ReferenceElement
    {
        bool finalized;

        ~this()
        {
            finalized = true;
        }
    }

    auto object = new ReferenceElement;
    StaticRingBuffer!(ReferenceElement, 1) buffer;

    assert(buffer.tryPushBack(object));
    buffer.popFront();

    assert(buffer.empty);
    assert(!object.finalized);
}

unittest
{
    // The inline raw-storage representation must advertise possible T
    // indirections to the GC even though live T objects are managed manually.
    static assert(hasIndirections!(StaticRingBuffer!(Object, 1)));
    static assert(!hasIndirections!(StaticRingBuffer!(int, 1)));
}

unittest
{
    // A nested indirection-bearing element must not make the raw-storage
    // overlay itself require an outer context. The fallback is deliberately
    // conservative until issue #10 resolves nested-element semantics.
    int outer;

    struct NestedElement
    {
        int opCall()
        {
            return ++outer;
        }
    }

    static assert(isNested!NestedElement);
    static assert(hasIndirections!NestedElement);
    static assert(__traits(compiles, StaticRingBuffer!(NestedElement, 2)()));
    static assert(hasIndirections!(StaticRingBuffer!(NestedElement, 2)));
}
