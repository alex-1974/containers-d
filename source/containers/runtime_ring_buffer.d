/**
 * Runtime-capacity owning FIFO ring buffer.
 *
 * RingBuffer is also re-exported from the package-root `containers` module.
 */
module containers.runtime_ring_buffer;

import containers.internal.element_lifetime :
    EndElementLifetimeOps,
    PlacementMoveOps,
    elementHasIndirections,
    elementNeedsDestruction;
import containers.internal.ring_sequence : RingSequenceOps;
import containers.internal.runtime_storage :
    RuntimeStorageAccessOps,
    RuntimeStorageOwner;
import core.lifetime : emplace, forward;
import std.traits : hasIndirections, isNested, Unqual;

/**
 * Owning bounded FIFO ring buffer with runtime-selected capacity.
 *
 * The backing storage is acquired once at construction and retained across
 * push/pop/clear operations. Exactly length slots contain live T objects.
 *
 * Copy construction is disabled because backing storage is uniquely owned.
 * Whole-buffer move transfers ownership in O(1) without relocating live
 * elements.
 */
struct RingBuffer(T)
{
    static assert(T.sizeof > 0,
        "RingBuffer requires an element type with non-zero size");
    static assert(!(is(T == struct) && isNested!T && hasIndirections!T),
        "RingBuffer v0.1 does not support nested/local struct element types with hidden context/indirections");

private:
    mixin PlacementMoveOps!T;
    mixin EndElementLifetimeOps!T;

    RuntimeStorageOwner!T _storage;
    mixin RuntimeStorageAccessOps!T;
    mixin RingSequenceOps;

    ref T borrowedSlot(
        size_t physicalIndex) scope return @trusted
    {
        // RuntimeStorageOwner owns this heap allocation uniquely. The compiler
        // sees only a stored pointer value and cannot prove that its lifetime
        // ends with this RingBuffer. This helper is the narrow bridge from
        // internal pointer provenance to the public owner-borrow contract.
        return *runtimeSlotPointer(physicalIndex);
    }

    ref const(T) borrowedSlot(
        size_t physicalIndex) const scope return @trusted
    {
        return *runtimeSlotPointer(physicalIndex);
    }

    T[] borrowedSlice(
        size_t physicalStart,
        size_t count) scope return @trusted @nogc nothrow
    {
        return runtimeSlotSlice(physicalStart, count);
    }

    const(T)[] borrowedSlice(
        size_t physicalStart,
        size_t count) const scope return @trusted @nogc nothrow
    {
        return runtimeSlotSlice(physicalStart, count);
    }

    void endSlotLifetime(size_t physicalIndex)
    {
        endElementLifetime(runtimeSlotPointer(physicalIndex));
        runtimeClearVacatedSlot(physicalIndex);
    }

public:
    /**
     * Acquires backing storage for capacity elements.
     *
     * Capacity zero is valid and produces the same observable inert state as
     * .init.
     */
    this(size_t capacity)
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
    this(return scope typeof(this) rhs)
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
    pragma(inline, true)
    size_t capacity() const @safe @nogc nothrow
    {
        // RuntimeStorageOwner is package-internal and its capacity field is
        // package-visible specifically so hot consumers do not need an
        // imported accessor call. Keep the public RingBuffer property while
        // exposing the raw word directly to local RingSequenceOps codegen.
        return _storage._capacity;
    }

    /// Number of live elements.
    pragma(inline, true)
    size_t length() const @safe @nogc nothrow
    {
        return _length;
    }

    /// Whether no live elements are stored.
    pragma(inline, true)
    bool empty() const @safe @nogc nothrow
    {
        return _length == 0;
    }

    /// Whether no additional element can be inserted.
    pragma(inline, true)
    bool full() const @safe @nogc nothrow
    {
        return _length == capacity;
    }

    /**
     * Mutable logical front element.
     *
     * Precondition: the buffer is not empty.
     */
    pragma(inline, true)
    ref T front() scope return
    {
        assert(!empty);
        return borrowedSlot(_head);
    }

    /// ditto
    pragma(inline, true)
    ref const(T) front() const scope return
    {
        assert(!empty);
        return *runtimeSlotPointer(_head);
    }

    /**
     * Mutable logical back element.
     *
     * Precondition: the buffer is not empty.
     */
    ref T back() scope return
    {
        assert(!empty);
        return borrowedSlot(physicalIndex(_length - 1));
    }

    /// ditto
    ref const(T) back() const scope return
    {
        assert(!empty);
        return *runtimeSlotPointer(physicalIndex(_length - 1));
    }

    /**
     * Mutable logical indexed access independent of physical wraparound.
     *
     * Precondition: logicalIndex is less than length.
     */
    ref T opIndex(size_t logicalIndex) scope return
    {
        assert(logicalIndex < _length);
        return borrowedSlot(physicalIndex(logicalIndex));
    }

    /// ditto
    ref const(T) opIndex(size_t logicalIndex) const scope return
    {
        assert(logicalIndex < _length);
        return *runtimeSlotPointer(physicalIndex(logicalIndex));
    }

    /**
     * Returns the first contiguous physical segment in logical FIFO order.
     *
     * The returned slice borrows the owned backing allocation. Successful
     * structural mutation, whole-buffer move, or destruction invalidates
     * previously returned segment slices.
     */
    T[] firstSegment() scope return @trusted @nogc nothrow
    {
        if (empty)
            return null;

        const physicalRemaining = capacity - _head;
        const count = _length < physicalRemaining
            ? _length
            : physicalRemaining;

        return borrowedSlice(_head, count);
    }

    /// ditto
    const(T)[] firstSegment() const scope return @trusted @nogc nothrow
    {
        if (empty)
            return null;

        const physicalRemaining = capacity - _head;
        const count = _length < physicalRemaining
            ? _length
            : physicalRemaining;

        return runtimeSlotSlice(_head, count);
    }

    /**
     * Returns the wrapped continuation after $(LREF firstSegment).
     *
     * The returned slice is empty whenever the logical sequence is physically
     * contiguous.
     */
    T[] secondSegment() scope return @trusted @nogc nothrow
    {
        if (empty)
            return null;

        const firstCount = firstSegment.length;
        return borrowedSlice(0, _length - firstCount);
    }

    /// ditto
    const(T)[] secondSegment() const scope return @trusted @nogc nothrow
    {
        if (empty)
            return null;

        const firstCount = firstSegment.length;
        return runtimeSlotSlice(0, _length - firstCount);
    }

    /**
     * Appends one element without overwriting existing contents.
     *
     * Returns false when full. A failed insertion leaves the logical sequence
     * unchanged.
     *
     * Lvalues use the ordinary `core.lifetime.emplace` construction path.
     * For an exact T rvalue whose type defines a D language move constructor,
     * the move constructor is invoked directly at the final storage address;
     * insertion therefore does not depend on the unresolved rvalue behavior of
     * `core.lifetime.emplace` tracked in issue #8.
     */
    static if (__traits(isScalar, T))
    {
        pragma(inline, true)
        bool tryPushBack()(T value)
        {
            if (full)
                return false;

            const physical = physicalIndex(_length);

            // Scalar T has no elaborate construction semantics. Match the
            // qualified StaticVector scalar strategy: use a plain typed store
            // instead of routing the common numeric/handle path through
            // generic core.lifetime.emplace / auto-ref transfer machinery.
            *runtimeSlotPointer(physical) = value;

            ++_length;
            return true;
        }
    }
    else
    {
        pragma(inline, true)
        bool tryPushBack(U)(auto ref U value)
        if (is(Unqual!U == T) &&
            __traits(compiles, emplace(cast(T*) null, forward!value)))
        {
            if (full)
                return false;

            const physical = physicalIndex(_length);

            static if (__traits(hasMoveConstructor, T) &&
                is(U == T) &&
                !__traits(isRef, value))
            {
                placementMoveConstruct(runtimeSlotPointer(physical), value);
            }
            else
            {
                emplace(runtimeSlotPointer(physical), forward!value);
            }

            ++_length;
            return true;
        }
    }

    /**
     * Destroys and removes the logical front element.
     *
     * Precondition: the buffer is not empty.
     */
    pragma(inline, true)
    void popFront()
    {
        assert(!empty);

        static if (elementNeedsDestruction!T ||
            elementHasIndirections!T)
        {
            const physical = _head;
            endSlotLifetime(physical);
        }

        consumeFrontState();
    }

    /**
     * Destroys all live elements while retaining the backing allocation.
     *
     * Trivial pointer-free T has no lifetime or GC-sanitation work, so clear
     * is an O(1) sequence-state reset. Nontrivial/indirection-bearing T keeps
     * the explicit per-slot lifetime path.
     */
    pragma(inline, true)
    void clear()
    {
        static if (elementNeedsDestruction!T ||
            elementHasIndirections!T)
        {
            while (!empty)
                popFront();
        }
        else
        {
            _head = 0;
            _length = 0;
        }
    }
}

///
unittest
{
    auto queue = RingBuffer!int(4);
    assert(queue.tryPushBack(10));
    assert(queue.tryPushBack(20));
    queue.popFront();
    assert(queue.front == 20);
    assert(queue.capacity == 4);
}

version (unittest)
{
    private struct RuntimeInsertMoveTestElement
    {
        static int moves;

        int value;
        int* self;

        this(int value)
        {
            this.value = value;
            self = &this.value;
        }

        @disable this(ref return scope RuntimeInsertMoveTestElement rhs);

        this(return scope RuntimeInsertMoveTestElement rhs)
        {
            value = rhs.value;
            self = &this.value;
            rhs.value = -1;
            rhs.self = null;
            ++moves;
        }

        bool selfValid() @safe @nogc nothrow
        {
            return self is &value;
        }
    }

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
    // Rvalue insertion must invoke the language move constructor at the final
    // heap slot address. Plain relocation from an intermediate value would
    // leave the self pointer referring to the wrong object.
    alias MoveOnly = RuntimeInsertMoveTestElement;

    MoveOnly.moves = 0;
    auto seed = MoveOnly(73);
    auto buffer = RingBuffer!MoveOnly(1);

    assert(buffer.tryPushBack(__rvalue(seed)));
    assert(buffer.front.value == 73);
    assert(buffer.front.selfValid);
    assert(MoveOnly.moves >= 1);
}

unittest
{
    // v0.1 deliberately rejects nested/local struct element types. Their
    // hidden context/frame lifetime is not part of the admitted contract.
    int outer;

    struct NestedElement
    {
        int opCall()
        {
            return ++outer;
        }
    }

    static assert(isNested!NestedElement);
    static assert(!__traits(compiles, RingBuffer!NestedElement(1)));
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
    // Trivial-element construction and steady-state operations are usable from
    // @safe @nogc nothrow code across the supported frontend matrix.
    // Whole-owner move is validated separately because frontend 2.112+
    // disallows the __rvalue(local) expression itself in @safe functions.
    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
            auto buffer = RingBuffer!int(5);

            assert(buffer.tryPushBack(1));
            assert(buffer.tryPushBack(2));
            buffer.popFront();
            assert(buffer.front == 2);
            buffer.clear();
        }();
    }));
}

unittest
{
    // A ring buffer stores a class reference as a value; pop must not invoke
    // the referenced object's class finalizer.
    class ReferenceElement
    {
        bool finalized;

        ~this()
        {
            finalized = true;
        }
    }

    auto object = new ReferenceElement;
    auto buffer = RingBuffer!ReferenceElement(1);

    assert(buffer.tryPushBack(object));
    buffer.popFront();

    assert(buffer.empty);
    assert(!object.finalized);
}

unittest
{
    auto buffer = RingBuffer!int(4);

    assert(buffer.firstSegment.length == 0);
    assert(buffer.secondSegment.length == 0);

    assert(buffer.tryPushBack(10));
    assert(buffer.tryPushBack(20));
    assert(buffer.tryPushBack(30));

    assert(buffer.firstSegment == [10, 20, 30]);
    assert(buffer.secondSegment.length == 0);

    buffer.popFront();
    buffer.popFront();

    assert(buffer.tryPushBack(40));
    assert(buffer.tryPushBack(50));
    assert(buffer.tryPushBack(60));

    assert(buffer.firstSegment == [30, 40]);
    assert(buffer.secondSegment == [50, 60]);
    assert(buffer.firstSegment.length + buffer.secondSegment.length == buffer.length);

    buffer.secondSegment[0] = 51;
    assert(buffer[2] == 51);
}

unittest
{
    // A full runtime ring with a non-zero head is represented by two physical
    // segments whose concatenation is the exact logical FIFO sequence.
    auto buffer = RingBuffer!int(4);

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
