/**
 * Bounded storage composed of independently owned contiguous segments.
 *
 * This module is intended for consumers that receive or produce data in
 * chunks and must not flatten those chunks into one large allocation.
 */
module containers.segmented_buffer;

import containers.internal.element_lifetime :
    EndElementLifetimeOps,
    elementHasIndirections,
    elementNeedsDestruction;
import containers.internal.runtime_storage :
    RuntimeStorageAccessOps,
    RuntimeStorageOwner;
import core.lifetime : emplace;
import std.traits : isNested;

/**
 * A bounded, single-threaded buffer whose contents remain segmented.
 *
 * `SegmentedBuffer!T` is useful when a consumer needs to append borrowed
 * chunks, expose the result as ordered chunks, and consume data from the
 * front without copying everything into one contiguous allocation. Each
 * segment is independently owned. Acquiring a later segment never moves an
 * earlier live segment, and consumed segments are retained for reuse.
 *
 * The buffer is bounded by `maximumLength`. `append` accepts as much input as
 * fits and reports the number accepted. `segment` exposes the remaining data
 * in one logical segment. `consume` removes data from the front and
 * `reset` starts a new logical batch while retaining acquired capacity.
 *
 * The type is single-threaded. It does not perform networking, retry,
 * backpressure, flattening, or implicit geometric growth policy.
 *
 * Example for a chunked byte consumer:
 *
 * ---
 * import containers : SegmentedByteBuffer;
 *
 * auto received = SegmentedByteBuffer(64 * 1024, 16 * 1024 * 1024);
 * const accepted = received.append(incomingChunk);
 * assert(accepted == incomingChunk.length);
 *
 * foreach (index; 0 .. received.segmentCount)
 *     send(received.segment(index));
 *
 * received.consume(bytesSent);
 * ---
 *
 * A segment slice borrows the buffer. Do not retain it across `append`,
 * `consume`, `reset`, owner move, or destruction.
 */
struct SegmentedBuffer(T)
{
    static assert(T.sizeof > 0,
        "SegmentedBuffer requires an element type with non-zero size");
    static assert(!(is(T == struct) && isNested!T),
        "SegmentedBuffer does not support nested/context-bearing structs");

private:
    struct Segment
    {
        RuntimeStorageOwner!T _storage;
        mixin RuntimeStorageAccessOps!T;
        size_t length;
        size_t consumed;

        this(size_t capacity)
        {
            _storage.initialize(capacity);
        }

        @disable this(ref return scope typeof(this) rhs);

        this(return scope typeof(this) rhs)
        {
            _storage.takeOwnershipFrom(rhs._storage);
            length = rhs.length;
            consumed = rhs.consumed;
            rhs.length = 0;
            rhs.consumed = 0;
        }

        ~this()
        {
            clear();
        }

        size_t capacity() const @safe @nogc nothrow
        {
            return _storage.capacity;
        }

        void clear()
        {
            static if (elementNeedsDestruction!T || elementHasIndirections!T)
            {
                while (length != consumed)
                {
                    --length;
                    endElementLifetime(runtimeSlotPointer(length));
                    runtimeClearVacatedSlot(length);
                }
            }
            length = 0;
            consumed = 0;
        }

        private void endElementLifetime(T* slot)
        {
            static if (elementNeedsDestruction!T)
                destroy!false(*slot);
        }
    }

    Segment*[] _segments;
    size_t _segmentSize;
    size_t _maximumLength;
    size_t _length;
    Segment*[] _reusableSegments;

    ref Segment backSegment() return
    {
        assert(_segments.length != 0);
        return *_segments[$ - 1];
    }

    void acquireSegment()
    {
        const remaining = _maximumLength - _length;
        const capacity = remaining < _segmentSize ? remaining : _segmentSize;
        assert(capacity != 0);
        if (_reusableSegments.length != 0)
        {
            auto segmentRef = _reusableSegments[$ - 1];
            _reusableSegments.length -= 1;
            segmentRef.clear();
            _segments ~= segmentRef;
        }
        else
            _segments ~= new Segment(capacity);
    }

    void discardConsumedFrontSegments()
    {
        while (_segments.length != 0 &&
            _segments[0].consumed == _segments[0].length)
        {
            auto segmentRef = _segments[0];
            segmentRef.clear();
            _reusableSegments ~= segmentRef;
            _segments = _segments[1 .. $];
        }
    }

public:
    /**
     * Creates an empty buffer.
     *
     * `segmentSize` is the preferred maximum size of each independently
     * stored chunk. `maximumLength` is the maximum number of live elements
     * the buffer can hold. No backing segment is acquired until the first
     * successful append.
     *
     * `segmentSize` must be non-zero. A zero `maximumLength` creates a valid
     * permanently full, empty buffer that accepts no input.
     */
    this(size_t segmentSize, size_t maximumLength)
    {
        assert(segmentSize != 0);
        _segmentSize = segmentSize;
        _maximumLength = maximumLength;
    }

    @disable this(ref return scope typeof(this) rhs);

    this(return scope typeof(this) rhs)
    {
        _segments = rhs._segments;
        _segmentSize = rhs._segmentSize;
        _maximumLength = rhs._maximumLength;
        _length = rhs._length;
        _reusableSegments = rhs._reusableSegments;
        rhs._segments = null;
        rhs._segmentSize = 0;
        rhs._maximumLength = 0;
        rhs._length = 0;
        rhs._reusableSegments = null;
    }

    @disable ref typeof(this) opAssign(ref typeof(this) rhs);

    ~this()
    {
        foreach (segmentRef; _segments)
        {
            segmentRef.clear();
            destroy(*segmentRef);
        }
        foreach (segmentRef; _reusableSegments)
        {
            segmentRef.clear();
            destroy(*segmentRef);
        }
    }

    /// Preferred maximum number of elements stored in one segment.
    size_t segmentSize() const @safe @nogc nothrow { return _segmentSize; }

    /// Maximum number of live elements held by the buffer.
    size_t capacity() const @safe @nogc nothrow { return _maximumLength; }

    /// Number of elements currently available for consumption.
    size_t length() const @safe @nogc nothrow { return _length; }

    /// Whether no elements are currently available.
    bool empty() const @safe @nogc nothrow { return _length == 0; }

    /// Whether no further elements can be appended.
    bool full() const @safe @nogc nothrow { return _length == _maximumLength; }

    /// Number of logical segments currently containing available elements.
    size_t segmentCount() const @safe @nogc nothrow
    {
        return _segments.length;
    }

    /**
     * Borrows one logical segment in consumption order.
     *
     * The returned slice contains the currently available portion of the
     * segment. `index` must be less than `segmentCount`. The slice is read-only
     * because the buffer's public append contract copies input into owned
     * storage; callers consume it with `consume`.
     */
    const(T)[] segment(size_t index) const scope return
    {
        assert(index < _segments.length);
        ref const s = *_segments[index];
        return s.runtimeSlotSlice(s.consumed, s.length - s.consumed);
    }

    /**
     * Appends as many values as fit and returns the number accepted.
     *
     * Input is copied into owned storage. Existing tail space is filled before
     * a new segment is acquired. If the input does not fit completely, the
     * return value is smaller than `values.length`; the already accepted
     * prefix remains valid and the remainder is not retained. A zero return
     * means the buffer is currently at its maximum length or `values` is
     * empty.
     *
     * Existing borrowed segment slices must be discarded after a successful
     * append.
     */
    size_t append(scope const(T)[] values)
    {
        size_t accepted;
        while (accepted != values.length && _length != _maximumLength)
        {
            if (_segments.length == 0 || backSegment.length ==
                backSegment.capacity)
                acquireSegment();

            ref segmentRef = backSegment;
            const available = segmentRef.capacity - segmentRef.length;
            const count = (values.length - accepted) < available
                ? values.length - accepted : available;

            foreach (i; 0 .. count)
                emplace(segmentRef.runtimeSlotPointer(segmentRef.length + i),
                    values[accepted + i]);

            backSegment.length += count;
            accepted += count;
            _length += count;
        }
        return accepted;
    }

    /**
     * Consumes up to `count` elements from the front without flattening.
     *
     * The return value is the number actually consumed, which is smaller than
     * `count` only when the buffer did not contain that many elements. Fully
     * consumed segments are recycled internally for later appends.
     * Existing borrowed segment slices must be discarded after a non-zero
     * result.
     */
    size_t consume(size_t count)
    {
        const target = count < _length ? count : _length;
        size_t consumed;
        while (consumed != target)
        {
            ref segmentRef = *_segments[0];
            const available = segmentRef.length - segmentRef.consumed;
            const take = (target - consumed) < available
                ? target - consumed : available;
            foreach (i; 0 .. take)
            {
                const index = segmentRef.consumed + i;
                static if (elementNeedsDestruction!T)
                    destroy!false(*segmentRef.runtimeSlotPointer(index));
                segmentRef.runtimeClearVacatedSlot(index);
            }
            segmentRef.consumed += take;
            consumed += take;
            _length -= take;
            discardConsumedFrontSegments();
        }
        return consumed;
    }

    /**
     * Ends all live element lifetimes and starts an empty reusable batch.
     *
     * Acquired segment capacity is retained for later appends. Existing
     * borrowed segment slices are invalid after reset.
     */
    void reset()
    {
        foreach (segmentRef; _segments)
            segmentRef.clear();
        _length = 0;
        foreach (segmentRef; _segments)
            _reusableSegments ~= segmentRef;
        _segments = null;
    }
}
/**
 * Byte-oriented name for `SegmentedBuffer!ubyte`.
 *
 * Use this type when a consumer receives HTTP bodies, file ranges, uploads, or
 * other byte streams in chunks. It has the same API as the generic buffer but
 * makes the intended payload type clear at the call site.
 *
 * ---
 * import containers : SegmentedByteBuffer;
 *
 * auto body = SegmentedByteBuffer(32 * 1024, 8 * 1024 * 1024);
 * const accepted = body.append(networkChunk);
 * if (accepted != networkChunk.length)
 *     handleCapacityLimit();
 * ---
 */
alias SegmentedByteBuffer = SegmentedBuffer!ubyte;

version (unittest)
{
    private struct SegmentedTracked
    {
        static size_t alive;
        int value;

        this(int value)
        {
            this.value = value;
            ++alive;
        }

        this(this)
        {
            ++alive;
        }

        ~this()
        {
            --alive;
        }
    }
}

unittest
{
    auto buffer = SegmentedByteBuffer(3, 8);
    const ubyte[] first = [1, 2, 3, 4, 5];

    assert(buffer.append(first) == 5);
    assert(buffer.length == 5);
    assert(buffer.segmentCount == 2);
    assert(buffer.segment(0) == [1, 2, 3]);
    assert(buffer.segment(1) == [4, 5]);

    const ubyte[] overflow = [6, 7, 8, 9];
    assert(buffer.append(overflow) == 3);
    assert(buffer.full);
    assert(buffer.append([10]) == 0);

    assert(buffer.consume(4) == 4);
    assert(buffer.length == 4);
    assert(buffer.segmentCount == 2);
    assert(buffer.segment(0) == [5, 6]);
    assert(buffer.segment(1) == [7, 8]);

    assert(buffer.consume(4) == 4);
    assert(buffer.empty);
    assert(buffer.append([9, 10, 11, 12, 13]) == 5);
    assert(buffer.segmentCount == 2);

    buffer.reset();
    assert(buffer.empty);
    assert(buffer.capacity == 8);
    assert(buffer.append([11, 12, 13]) == 3);
}

unittest
{
    SegmentedTracked.alive = 0;
    {
        auto buffer = SegmentedBuffer!SegmentedTracked(2, 5);
        SegmentedTracked[3] values = [
            SegmentedTracked(1),
            SegmentedTracked(2),
            SegmentedTracked(3)];

        assert(buffer.append(values[]) == 3);
        assert(SegmentedTracked.alive >= 3);
        assert(buffer.consume(2) == 2);
        buffer.reset();
    }
    assert(SegmentedTracked.alive == 0);
}

unittest
{
    auto source = SegmentedByteBuffer(2, 6);
    assert(source.append([1, 2, 3, 4]) == 4);
    assert(source.consume(2) == 2);
    assert(source.append([5, 6]) == 2);

    auto moved = __rvalue(source);
    assert(source.empty);
    assert(source.capacity == 0);
    assert(moved.length == 4);
    assert(moved.segmentCount == 2);
    assert(moved.segment(0) == [3, 4]);
    assert(moved.segment(1) == [5, 6]);
}
