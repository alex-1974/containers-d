/**
 * Reusable contiguous typed scratch storage.
 *
 * ScratchBuffer is also re-exported from the package-root `containers` module.
 */
module containers.scratch_buffer;

import containers.internal.element_lifetime :
    EndElementLifetimeOps,
    PlacementMoveOps,
    elementHasIndirections,
    elementNeedsDestruction;
import containers.internal.runtime_storage :
    RuntimeStorageAccessOps,
    RuntimeStorageOwner;
import core.lifetime : emplace, forward;
import std.traits : hasIndirections, isNested, Unqual;

/**
 * Reusable runtime-capacity contiguous typed buffer.
 *
 * ScratchBuffer owns one backing allocation and exposes an exact live
 * contiguous prefix. Reset ends the live element lifetimes while retaining the
 * established backing capacity for later reuse.
 *
 * The first public family is thread-confined. It does not provide
 * synchronization, pooling, heterogeneous arena allocation, automatic shrink,
 * or live-element reallocation.
 */
struct ScratchBuffer(T)
{
    static assert(T.sizeof > 0,
        "ScratchBuffer requires an element type with non-zero size");
    static assert(!(is(T == struct) && isNested!T && hasIndirections!T),
        "ScratchBuffer does not support nested/local struct element types with hidden context/indirections");

private:
    mixin PlacementMoveOps!T;
    mixin EndElementLifetimeOps!T;

    RuntimeStorageOwner!T _storage;
    mixin RuntimeStorageAccessOps!T;

    size_t _length;

    ref T borrowedSlot(
        size_t index) scope return @trusted
    {
        return *runtimeSlotPointer(index);
    }

    ref const(T) borrowedSlot(
        size_t index) const scope return @trusted
    {
        return *runtimeSlotPointer(index);
    }

    void endSlotLifetime(size_t index)
    {
        endElementLifetime(runtimeSlotPointer(index));
        runtimeClearVacatedSlot(index);
    }

public:
    /**
     * Establishes one backing allocation for capacity elements.
     *
     * Capacity zero is valid and produces the inert .init-equivalent state.
     */
    this(size_t capacity)
    {
        _storage.initialize(capacity);
    }

    /// Unique owning storage is never copied implicitly.
    @disable this(ref return scope typeof(this) rhs);

    /**
     * Transfers the backing allocation without relocating live T values.
     *
     * The moved-from source becomes the inert .init-equivalent state.
     */
    this(return scope typeof(this) rhs)
    {
        _storage.takeOwnershipFrom(rhs._storage);
        _length = rhs._length;
        rhs._length = 0;
    }

    /// Identity assignment is deliberately unavailable.
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

    /// Whether no live elements are stored.
    bool empty() const @safe @nogc nothrow
    {
        return _length == 0;
    }

    /// Whether the established backing capacity is fully occupied.
    bool full() const @safe @nogc nothrow
    {
        return _length == capacity;
    }

    /**
     * Mutable indexed access to one live element.
     *
     * Precondition: index is less than length.
     */
    ref T opIndex(size_t index) scope return
    {
        assert(index < _length);
        return borrowedSlot(index);
    }

    /// ditto
    ref const(T) opIndex(size_t index) const scope return
    {
        assert(index < _length);
        return borrowedSlot(index);
    }

    /**
     * Borrows the exact live contiguous prefix.
     *
     * Successful structural mutation, reset, successful capacity growth,
     * whole-buffer move, or destruction invalidates previously returned
     * slices.
     */
    pragma(inline, true)
    T[] opSlice()() scope return @trusted @nogc nothrow
    {
        return (cast(T*) _storage._bytes.ptr)[0 .. _length];
    }

    /// ditto
    pragma(inline, true)
    const(T)[] opSlice()() const scope return @trusted @nogc nothrow
    {
        return (cast(const(T)*) _storage._bytes.ptr)[0 .. _length];
    }

    /**
     * Ensures at least minCapacity backing slots without relocating live T.
     *
     * Returns true when the current capacity already satisfies minCapacity.
     *
     * If growth is required while live elements exist, returns false and
     * leaves the buffer unchanged.
     *
     * If growth is required while empty, replaces the backing allocation with
     * exactly minCapacity slots. No geometric growth policy is embedded in the
     * container.
     *
     * Allocation failure follows the runtime-storage fatal OOM contract.
     */
    bool tryReserve(size_t minCapacity) @safe @nogc nothrow
    {
        if (minCapacity <= capacity)
            return true;

        if (!empty)
            return false;

        _storage.replaceEmptyCapacity(minCapacity);
        return true;
    }

    /**
     * Appends one live element when spare established capacity exists.
     *
     * Returns false when full. A failed insertion performs no allocation and
     * leaves the live prefix unchanged.
     */
    pragma(inline, true)
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
            placementMoveConstruct(runtimeSlotPointer(index), value);
        }
        else
        {
            emplace(runtimeSlotPointer(index), forward!value);
        }

        ++_length;
        return true;
    }

    /**
     * Ends all live element lifetimes while retaining backing capacity.
     *
     * Trivial pointer-free T specializes to an O(1) logical reset.
     */
    pragma(inline, true)
    void reset()()
    {
        static if (!elementNeedsDestruction!T &&
            !elementHasIndirections!T)
        {
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

///
unittest
{
    auto scratch = ScratchBuffer!int(4);

    assert(scratch.tryPushBack(10));
    assert(scratch.tryPushBack(20));
    assert(scratch[] == [10, 20]);

    scratch.reset();

    assert(scratch.empty);
    assert(scratch.capacity == 4);
}

version (unittest)
{
    private struct ScratchTracked
    {
        static size_t alive;
        static size_t destroyed;

        int value;

        this(int value)
        {
            this.value = value;
            ++alive;
        }

        this(ref return scope ScratchTracked rhs)
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

    private struct ScratchOverAligned
    {
        align(64) ulong value;
    }

    private struct ScratchWithIndirection
    {
        Object reference;
        size_t value;
    }
}

unittest
{
    ScratchBuffer!int initial;

    assert(initial.capacity == 0);
    assert(initial.length == 0);
    assert(initial.empty);
    assert(initial.full);
    assert(!initial.tryPushBack(1));
}

unittest
{
    auto scratch = ScratchBuffer!int(4);

    assert(scratch.tryPushBack(10));
    assert(scratch.tryPushBack(20));
    assert(scratch.tryPushBack(30));

    const ptrBefore = &scratch[0];

    scratch.reset();

    assert(scratch.empty);
    assert(scratch.capacity == 4);

    assert(scratch.tryPushBack(40));
    assert(&scratch[0] is ptrBefore);
    assert(scratch[] == [40]);
}

unittest
{
    ScratchBuffer!int scratch;

    assert(scratch.tryReserve(8));
    assert(scratch.capacity == 8);

    assert(scratch.tryPushBack(1));
    const beforePtr = &scratch[0];

    assert(scratch.tryReserve(4));
    assert(scratch.capacity == 8);
    assert(&scratch[0] is beforePtr);

    assert(scratch.tryPushBack(2));

    assert(!scratch.tryReserve(16));
    assert(scratch.capacity == 8);
    assert(scratch[] == [1, 2]);

    scratch.reset();

    assert(scratch.tryReserve(16));
    assert(scratch.capacity == 16);
    assert(scratch.empty);
}

unittest
{
    ScratchTracked.alive = 0;
    ScratchTracked.destroyed = 0;

    {
        auto scratch = ScratchBuffer!ScratchTracked(3);
        auto value = ScratchTracked(7);

        assert(scratch.tryPushBack(value));
        assert(scratch.tryPushBack(value));
        assert(ScratchTracked.alive == 3);

        scratch.reset();

        assert(ScratchTracked.alive == 1);
        assert(ScratchTracked.destroyed == 2);
        assert(scratch.capacity == 3);
    }

    assert(ScratchTracked.alive == 0);
}

unittest
{
    ScratchBuffer!ScratchOverAligned scratch;

    assert(scratch.tryReserve(2));
    assert(scratch.tryPushBack(ScratchOverAligned(41)));
    assert((cast(size_t) &scratch[0]) % ScratchOverAligned.alignof == 0);

    scratch.reset();

    assert(scratch.tryReserve(5));
    assert(scratch.tryPushBack(ScratchOverAligned(42)));
    assert((cast(size_t) &scratch[0]) % ScratchOverAligned.alignof == 0);
}

unittest
{
    static assert(hasIndirections!ScratchWithIndirection);

    ScratchBuffer!ScratchWithIndirection scratch;
    auto object = new Object;

    assert(scratch.tryReserve(1));
    assert(scratch.tryPushBack(ScratchWithIndirection(object, 1)));
    assert(scratch[0].reference is object);

    scratch.reset();

    assert(scratch.tryReserve(4));
    assert(scratch.tryPushBack(ScratchWithIndirection(object, 2)));
    assert(scratch[0].reference is object);

    scratch.reset();
    assert(scratch.empty);
}

unittest
{
    auto source = ScratchBuffer!int(4);
    assert(source.tryPushBack(1));
    assert(source.tryPushBack(2));

    auto moved = __rvalue(source);

    assert(source.capacity == 0);
    assert(source.length == 0);
    assert(source.empty);

    assert(moved.capacity == 4);
    assert(moved[] == [1, 2]);
}

unittest
{
    static assert(__traits(compiles, {
        () @safe @nogc nothrow {
            ScratchBuffer!int scratch;

            assert(scratch.tryReserve(8));
            assert(scratch.tryPushBack(1));
            assert(scratch.tryPushBack(2));
            assert(scratch[] == [1, 2]);

            assert(!scratch.tryReserve(16));

            scratch.reset();

            assert(scratch.tryReserve(16));
            assert(scratch.empty);
            assert(scratch.capacity == 16);
        }();
    }));
}
