# containers-d

High-performance generic container primitives for D.

Current release: `v0.1.1`.

The 0.x line is the API-stabilization period. Minor 0.x releases may make
breaking public-API changes when required by evidence; patch releases should
not intentionally break source compatibility.

## Installation

Install the published package through the DUB registry:

```bash
dub add containers-d@0.1.1
```

The published v0.1.1 package root contains the ring-buffer family:

```d
import containers : RingBuffer, StaticRingBuffer;
```

The current unreleased development branch additionally exports:

```d
import containers :
    BlockingQueue,
    BlockingQueuePopResult,
    BlockingQueuePopStatus,
    BlockingQueuePushResult,
    ScratchBuffer,
    StaticVector,
    WorkStealingDeque,
    WorkStealingTakeResult;
```

## Compatibility

Minimum supported D frontend:

```text
2.111.0
```

Normal development is continuously checked with DMD 2.111 and LDC 1.41. The
v0.1 release gate additionally qualifies DMD 2.112/2.113 and LDC 1.42/1.43 and
runs portability jobs on Linux, Windows and macOS.

Sequential container families remain unsynchronized. Concurrent semantics are
represented by separate public types rather than policy switches. Nested/local
struct element types carrying an outer context remain excluded where their
hidden context/lifetime contract is not qualified; issue #10 owns that research.

## Static vector

The unreleased development branch adds `StaticVector!(T, Capacity)`: a
compile-time fixed-capacity, runtime-length contiguous vector with inline
storage and no backing allocation.

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
capacity. `tryPushBack` is the checked non-overwriting form. `vector[]`
borrows exactly the live contiguous prefix and must not outlive its owner.

Scalar element types use an automatically selected direct inline
representation. Non-trivial types use the qualified lifetime/storage machinery
for construction, destruction, GC visibility and alignment. Those choices are
implementation details, not public policy parameters.

## Scratch buffer

The unreleased development branch adds `ScratchBuffer!T`, a reusable
runtime-capacity contiguous typed buffer for temporary work storage.

```d
import containers : ScratchBuffer;

ScratchBuffer!int scratch;

assert(scratch.tryReserve(64));

assert(scratch.tryPushBack(10));
assert(scratch.tryPushBack(20));
assert(scratch[] == [10, 20]);

scratch.reset();

assert(scratch.empty);
assert(scratch.capacity == 64);
```

`reset()` ends the live element lifetimes but retains the backing allocation.
For trivial pointer-free elements this specializes to an O(1) logical reset.

Capacity can be increased between work phases with `tryReserve`. If growth is
required while live elements exist, the operation returns `false` and leaves
the buffer unchanged. ScratchBuffer never relocates live elements and does not
embed automatic geometric growth or shrink policy.

The first family is thread-confined. Arena allocation, BufferPool semantics,
live-content reallocation, public UniqueBuffer ownership, and allocator-policy
customization remain outside this API.

## Work-stealing deque

The unreleased development branch adds
`WorkStealingDeque!(T, Capacity)`, a bounded fixed-capacity concurrent deque
for exactly one owner and zero or more thief threads.

```d
import containers : WorkStealingDeque;

WorkStealingDeque!(ulong, 8) queue;

assert(queue.tryPush(10));
assert(queue.tryPush(20));

auto stolen = queue.steal();
assert(stolen.found);
assert(stolen.value == 10);

auto owner = queue.pop();
assert(owner.found);
assert(owner.value == 20);
```

The owner calls `tryPush` and `pop`; thieves call `steal` or
`stealBatch`. The deque never resizes and does not choose scheduler overflow,
parking, reclamation, or execution policy. A failed `tryPush` reports only
that the bounded deque is full.

Batch stealing writes into caller-owned storage:

```d
ulong[4] batch;
const taken = queue.stealBatch(batch[]);
```

The first public API intentionally has no `size`, `empty`, or `full`
snapshot. Such concurrent observations are immediately stale; the operation
results are the actionable contract.

The deque transports trivial atomically shared-compatible value
representations and does not own referenced objects. Copy construction, move
construction, assignment, and pass-by-value use are rejected because the
concurrent object has identity. The hot operations are `@safe @nogc nothrow`,
but `@safe` cannot enforce the one-owner protocol.

## Blocking queue

The unreleased development branch adds `BlockingQueue!T`, a bounded
runtime-capacity synchronized FIFO for multiple producers and multiple
consumers.

```d
import containers :
    BlockingQueue,
    BlockingQueuePopStatus,
    BlockingQueuePushResult;

auto queue = new BlockingQueue!int(64);

assert(queue.tryPush(10) == BlockingQueuePushResult.pushed);

auto item = queue.waitPop();
assert(item.found);
assert(item.value == 10);

assert(queue.close);
assert(queue.waitPop().status == BlockingQueuePopStatus.closed);
```

Producer admission is intentionally non-blocking. `tryPush` returns
`pushed`, `full`, or `closed`; it never waits for free capacity.
`waitPop` blocks only while the queue is empty and open.

`close()` is idempotent. Closing rejects future pushes, preserves values
already queued for normal FIFO draining, and wakes every blocked consumer.
A consumer observes `closed` only after the closed queue has been fully
drained. Condition-variable waits always re-check the state predicate, so
spurious notifications do not alter queue semantics.

The first public family accepts copyable element types. Move-only synchronized
transfer remains deferred until its lifetime contract is independently
qualified. Construction may allocate the fixed backing FIFO and synchronization
objects; ordinary queue operations do not resize or reacquire FIFO backing
storage.

The initial concurrent API intentionally exposes no `length`, `empty`,
`full`, or `closed` snapshots because such observations may become stale
immediately. The immutable `capacity` property and operation results provide
the actionable state contract.

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

Live inline slots preserve `T.alignof`, including over-aligned element types when
the buffer is embedded in another aggregate. On compiler/target combinations
that do not propagate such aggregate alignment reliably, the implementation
uses inline alignment slack rather than heap storage.

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

The fixed- and runtime-capacity ring-buffer families are released through
v0.1.1. The current development line additionally contains the qualified
`StaticVector!(T, Capacity)`, `ScratchBuffer!T`,
`WorkStealingDeque!(T, Capacity)`, and `BlockingQueue!T` families.

Future candidates include:

- heterogeneous Arena and BufferPool families where separately justified;
- separately designed SPSC/MPSC/MPMC concurrent families where justified.

Materially different storage, ownership, overflow, allocation or concurrency
semantics are represented explicitly rather than hidden behind one ambiguous
container type.

See `ROADMAP.md`, `docs/design/`, and `docs/validation.md`.
