# SegmentedBuffer public API

Status: admitted v0.3.0 public contract  
Tracking: issues #85–#92

## Purpose

`SegmentedBuffer!T` is a bounded, single-threaded buffer for consumers that
receive or produce values in chunks. It keeps the data in independently owned
contiguous segments so a consumer can process or send the chunks in order
without first flattening them into one large allocation.

The byte-oriented name is:

```d
alias SegmentedByteBuffer = SegmentedBuffer!ubyte;
```

`SegmentedByteBuffer` is the intended entry point for HTTP bodies, range
transfers, file chunks, uploads and other byte-oriented I/O. The generic type
is useful when the same segmented lifecycle applies to a copyable typed value.

This family is not a ring buffer, a vector, a stream, a queue, or a networking
policy object. It does not synchronize producers and consumers, retry failed
I/O, apply backpressure, or hide flattening.

## Public module

```d
import containers.segmented_buffer :
    SegmentedBuffer,
    SegmentedByteBuffer;
```

The package root re-exports both names:

```d
import containers : SegmentedBuffer, SegmentedByteBuffer;
```

## Typical byte consumer

```d
auto body = SegmentedByteBuffer(64 * 1024, 16 * 1024 * 1024);

const accepted = body.append(receivedChunk);
if (accepted != receivedChunk.length)
{
    // The caller decides whether to retry the remainder or report a limit.
    handleMaximumLength();
}

foreach (index; 0 .. body.segmentCount)
    send(body.segment(index));

body.consume(bytesSuccessfullySent);
```

The buffer copies `receivedChunk` into owned storage. The input may therefore
be a temporary callback slice and does not need to remain alive after
`append` returns.

## Construction and capacity

```d
auto buffer = SegmentedByteBuffer(segmentSize, maximumLength);
```

`segmentSize` is the preferred maximum number of elements in one segment.
`maximumLength` is the maximum number of currently available elements across
all logical segments.

Construction does not acquire a segment. The first successful append acquires
one. `segmentSize` must be non-zero. A zero `maximumLength` is valid but can
never accept input.

The public observations are:

```text
segmentSize  preferred maximum size of a segment
capacity     maximum logical length
length       currently available element count
empty        length == 0
full         length == capacity
segmentCount number of logical segments with available data
```

## Append

```d
size_t append(scope const(T)[] values);
```

Append copies values into owned storage and returns the number accepted.

- Existing tail space is filled first.
- A new segment is acquired only when the current tail is full.
- No existing live segment is relocated when a later segment is acquired.
- If the maximum length is reached, only the fitting prefix is accepted.
- The remainder is not retained and is not silently discarded by policy; the
  return value tells the caller exactly how much was accepted.
- An empty input returns zero and does not change the buffer.
- Successful append invalidates previously borrowed segment slices.

For generic `T`, the input must be constructible from `const(T)`. The first
public API intentionally uses copy-style append because it matches chunked
consumer input. A future move-append operation would require a separate
contract for non-copyable elements.

## Reading segments

```d
const(T)[] segment(size_t index) const scope return;
```

`segment(index)` returns the currently available portion of one logical
segment, in consumption order. Segment zero is the next data at the logical
front; the last segment is the current append tail.

The returned slice is read-only and borrowed. It does not own the buffer or
extend its lifetime. `index` must be less than `segmentCount`.

The slice must not be retained across:

- successful `append`;
- non-zero `consume`;
- `reset`;
- whole-buffer move;
- destruction.

Acquiring a later segment does not move earlier segment storage. This protects
the common consumer pattern of visiting the segments in order, but callers
still discard all views after any structural mutation.

## Consumption

```d
size_t consume(size_t count);
```

`consume` removes up to `count` elements from the logical front and returns
the number actually removed.

- It never flattens or shifts the remaining data.
- It may consume across multiple segments.
- A count larger than `length` consumes only the available data.
- Fully consumed segments leave the logical segment sequence.
- Their capacity is retained internally and reused by later appends.
- A non-zero result invalidates existing segment slices.

This lets a sender acknowledge only the prefix it successfully processed:

```d
const sent = sendAvailable(buffer.segment(0));
buffer.consume(sent);
```

The caller must account for segments after the first when `sent` spans a
segment boundary.

## Reset and reuse

```d
void reset();
```

`reset` ends all live element lifetimes, clears the logical sequence, and
retains acquired segment capacity for a later batch. It does not flatten,
shrink, or apply an automatic growth policy.

All borrowed slices are invalid after reset.

## Ownership and move

The buffer uniquely owns its segments.

- implicit copy construction is disabled;
- identity assignment is disabled;
- whole-buffer move transfers the segment ownership in O(1);
- live elements stay at the same addresses during owner move;
- the moved-from buffer becomes an inert zero-capacity state;
- destruction releases all active and recyclable segments exactly once.

The type is thread-confined. `@safe` does not establish a cross-thread
protocol, and no synchronization is implied by the segmented representation.

## Element lifetime, alignment and GC visibility

Exactly `length` elements are live. A segment's unused slots do not contain
live `T` values merely because storage has been acquired.

For generic `T`:

- append begins each element lifetime in its final segment slot;
- consume ends each consumed lifetime exactly once;
- reset ends all remaining lifetimes;
- destruction ends remaining lifetimes before releasing storage;
- `T.alignof` is preserved for every segment;
- indirection-bearing storage is made visible to the D GC;
- vacated indirection-bearing slots are cleared to remove stale conservative
  roots.

Nested/context-bearing struct element types remain rejected under the existing
containers-d element contract.

## Allocation contract

Construction is allocation-free until the first successful append. A positive
append may acquire one or more independently owned segments. Existing segment
capacity is reused after consumption or reset.

The container does not expose an allocator parameter. It does not reallocate
or relocate live segments, and it does not perform hidden flattening. Element
operations may have their own allocation behavior.

## Performance and validation

The release gate qualifies:

- DMD 2.111 and LDC 1.41 correctness;
- the controlled release compiler matrix;
- external consumer and DIP1000 borrow tests;
- GC reachability and over-alignment;
- candidate, direct segmented and flattening baseline workloads;
- package-root and exported-archive consumers;
- Linux ARM64, Windows x64, macOS Intel and macOS ARM64 portability.

The reproducible performance probe is
`benchmarks/segmented_buffer_append_probe.d`.
