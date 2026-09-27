# containers-d

High-performance generic container primitives for D.

Status: pre-release.

## Ring buffers

containers-d provides two bounded, single-threaded FIFO ring-buffer families:

- `StaticRingBuffer!(T, Capacity)` — compile-time capacity with inline storage;
- `RingBuffer!T` — runtime-selected capacity with one owned backing allocation.

### Static capacity

`StaticRingBuffer!(T, Capacity)` keeps its storage inline.

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

Whole-buffer copy construction is available when `T` is copyable.
Whole-buffer move construction preserves D language move constructors when
present and otherwise uses the classic relocation/`opPostMove` path.

### Runtime capacity

```d
import containers : RingBuffer;

auto queue = RingBuffer!int(1024);

assert(queue.tryPushBack(10));
assert(queue.tryPushBack(20));
queue.popFront();
assert(queue.front == 20);
```

`RingBuffer!T.init` and explicit capacity zero are inert, empty states.
Positive capacity acquires one aligned backing allocation. Implicit copy and
identity assignment are disabled; whole-buffer move transfers ownership in O(1)
without relocating live elements.

`clear` destroys live elements but retains backing capacity. Ordinary
push/pop/clear do not reacquire backing storage.

Wrapped runtime contents are exposed as `firstSegment` followed by
`secondSegment`. These slices borrow the owning buffer and are invalidated by
successful structural mutation, owner move, or destruction.

For element types containing GC-visible indirections, the external storage is
registered with the D GC while owned and vacated slots are cleared to avoid
stale conservative roots.

## Direction

The fixed- and runtime-capacity ring-buffer families are implemented and their
current hot paths have been qualified on the baseline DMD/LDC toolchains. The
package remains pre-release while release readiness is evaluated.

Future candidates include:

- FIFO queues;
- LIFO/FILO stacks;
- deque-like structures where justified;
- separately designed concurrent SPSC/MPMC structures.

Materially different storage, ownership, overflow, allocation or concurrency
semantics are represented explicitly rather than hidden behind one ambiguous
container type.

See `ROADMAP.md`, `docs/design/`, and `docs/validation.md`.
