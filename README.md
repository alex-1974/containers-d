# containers-d

High-performance generic container primitives for D.

Status: pre-release.

## Ring buffer

The first admitted container is `StaticRingBuffer!(T, Capacity)`: a bounded,
single-threaded FIFO ring buffer with compile-time capacity and inline storage.

```d
import containers : StaticRingBuffer;

StaticRingBuffer!(int, 4) queue;

assert(queue.tryPushBack(10));
assert(queue.tryPushBack(20));

assert(queue.front == 10);
queue.popFront();
assert(queue.front == 20);
```

The ordinary insertion operation never overwrites existing elements. When the
buffer is full, `tryPushBack` returns `false` and leaves the logical sequence
unchanged.

The buffer itself performs no heap allocation for construction or steady-state
push/pop operations. Operations performed by the element type `T` may still
allocate.

For zero-copy bulk access, the current logical FIFO sequence is available as at
most two borrowed contiguous slices:

```d
auto first = queue.firstSegment;
auto second = queue.secondSegment;

// Logical order is exactly:
// first followed by second.
assert(first.length + second.length == queue.length);
```

The slices borrow the buffer's inline storage. Successful structural mutation
invalidates previously returned segment slices; a failed `tryPushBack` on a
full buffer does not.

Whole-buffer copy construction is available when `T` is copyable. Whole-buffer
move construction currently excludes element types that define a D language
move constructor; that toolchain/lifetime boundary is tracked in issue #3.

## Direction

Future candidates include:

- runtime-capacity ring buffers;
- FIFO queues;
- LIFO/FILO stacks;
- contiguous segment access for wrapped storage;
- separately designed concurrent SPSC/MPMC structures.

Materially different storage, ownership, overflow, allocation or concurrency
semantics are represented explicitly rather than hidden behind one ambiguous
container type.

See `ROADMAP.md`, `docs/design/`, and `docs/validation.md`.
