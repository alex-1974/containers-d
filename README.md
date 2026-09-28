# containers-d

High-performance generic container primitives for D.

Current release: `v0.1.0`.

The 0.x line is the API-stabilization period. Minor 0.x releases may make
breaking public-API changes when required by evidence; patch releases should
not intentionally break source compatibility.

## Installation

Install the published package through the DUB registry:

```bash
dub add containers-d@0.1.0
```

The published `v0.1.0` package root contains the ring-buffer family:

```d
import containers : RingBuffer, StaticRingBuffer;
```

The current unreleased development branch additionally exports:

```d
import containers : StaticVector;
```

## Compatibility

Minimum supported D frontend:

```text
2.111.0
```

Normal development is continuously checked with DMD 2.111 and LDC 1.41. The
v0.1 release gate additionally qualifies DMD 2.112/2.113 and LDC 1.42/1.43 and
runs portability jobs on Linux, Windows and macOS.

The public containers are single-threaded. Nested/local struct element types
carrying an outer context are deliberately not admitted where their hidden
context/lifetime contract is not yet qualified; issue #10 owns research into
that category. Concurrent SPSC/MPSC/MPMC containers, if added later, are
separate type families.

## Static vector

The unreleased development branch adds
`StaticVector!(T, Capacity)`: a compile-time fixed-capacity, runtime-length
contiguous vector with inline storage.

```d
import containers : StaticVector;

StaticVector!(int, 4) values;

values.pushBack(10);
values.pushBack(20);

assert(values.length == 2);
assert(values.front == 10);
assert(values.back == 20);
assert(values[] == [10, 20]);

values.popBack();
assert(values[] == [10]);
```

`pushBack` is the precondition-based hot-path operation and requires spare
capacity. `tryPushBack` is the checked non-overwriting form and returns
`false` when full.

`vector[]` is a borrowed view of exactly the live contiguous prefix. It aliases
the vector's inline storage and must not outlive the owner.

The vector itself performs no backing allocation. Element construction,
destruction or user-defined operations may have their own allocation behavior.
Scalar element types use an automatically selected direct inline representation;
non-trivial types use the qualified lifetime/storage path for destruction, GC
visibility and alignment. These are implementation choices rather than public
policy parameters.

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

The fixed- and runtime-capacity ring-buffer families are released in v0.1.0.
The next qualified development candidate is `StaticVector!(T, Capacity)`,
derived from real geo-d/geo3-d consumers and qualified for runtime behavior,
lifetime safety, build cost and portability before package-root promotion.

Future candidates include:

- FIFO queues;
- LIFO/FILO stacks;
- deque-like structures where justified;
- separately designed concurrent SPSC/MPMC structures.

Materially different storage, ownership, overflow, allocation or concurrency
semantics are represented explicitly rather than hidden behind one ambiguous
container type.

See `ROADMAP.md`, `docs/design/`, and `docs/validation.md`.
