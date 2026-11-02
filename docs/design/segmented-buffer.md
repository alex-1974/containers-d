# Segmented buffer contract

Status: admitted v0.3.0 implementation contract.

`SegmentedBuffer!T` and its byte-oriented alias `SegmentedByteBuffer` are
bounded, single-threaded buffers composed of independently owned contiguous
segments. They are intended for chunked I/O and other consumers that must
preserve segmentation rather than flattening data into one allocation.

## Ownership and capacity

The buffer owns every acquired segment. `segmentSize` is the maximum capacity
of a segment and `maximumLength` is the maximum logical number of elements.
Segments are acquired only as append requires them. An acquired segment is
never relocated when a later segment is acquired.

The first implementation uses the existing aligned runtime storage and
element-lifetime machinery. The segment table is internal; callers borrow
individual segment slices through `segment(index)`.

## Append

```d
size_t append(scope const(T)[] values);
```

Append fills the current tail segment before acquiring another segment. It
returns the number of accepted elements. If the maximum length is reached,
the operation returns zero for the remaining input and never overwrites live
values.

The current generic implementation requires `T` to be constructible from a
`const(T)` value. A future move-append operation may extend this without
changing the ownership contract.

## Consumption and reset

`consume(count)` destroys and removes up to `count` elements from the logical
front without flattening. Fully consumed segments are removed from the
logical segment sequence and retained internally for later reuse. Repeated
receive/consume cycles therefore do not require unbounded new segment
allocations.

`reset()` ends all remaining element lifetimes, retains acquired segment
capacity, and returns the logical length to zero.

## Borrowing

`segment(index)` returns a borrowed slice of the unconsumed portion of one
logical segment. The slice must not outlive the owning buffer. Structural
mutation, consumption, reset, owner move and destruction invalidate borrowed
slices. A later segment acquisition does not relocate earlier segments, but
callers must not retain a segment slice across any mutation unless a stronger
guarantee is added by a future contract.

## Explicit non-goals

The family does not provide implicit geometric growth, flattening, allocator
customization, synchronization, networking policy, retries, or backpressure.
`SegmentedByteBuffer` is an alias of `SegmentedBuffer!ubyte`; it exists to give
byte-oriented consumers a discoverable and semantically precise entry point.
