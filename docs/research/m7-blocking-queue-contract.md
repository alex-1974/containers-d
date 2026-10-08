# M7 bounded BlockingQueue research contract

Status: Stage 1 active research  
Tracking: issue #28

## Question

Can containers-d provide a reusable bounded blocking FIFO family for the
independent DCanvas and raster-stage-mailbox requirements without contaminating
RingBuffer with synchronization policy?

## Layering

```text
ResearchBlockingQueue!T
├── Mutex + Condition + closed state
└── RingBuffer!T
```

RingBuffer remains an unsynchronized bounded FIFO owner.

## Stage 1 topology

The synchronization contract permits multiple producers and multiple consumers
under one mutex.

This is not a lock-free MPMC claim. Lock-free SPSC/MPSC/MPMC remain separate
families.

## Producer result

```d
enum BlockingQueuePushResult
{
    pushed,
    full,
    closed,
}
```

`tryPush` never waits for capacity:

- open + spare slot -> pushed;
- open + full -> full;
- closed -> closed.

Close therefore cannot be confused with temporary backpressure.

## Consumer result

```d
enum BlockingQueuePopStatus
{
    value,
    closed,
}
```

`waitPop` blocks only while:

```text
empty && !closed
```

After close:

- queued values continue to drain in FIFO order;
- once empty, waitPop returns closed immediately;
- every currently blocked consumer is notified.

The wait predicate is always checked in a loop so spurious wakeups are
semantically harmless.

## Element contract — Stage 1

Stage 1 deliberately requires copyable T.

Reason: RingBuffer currently exposes borrowed front access followed by
destructive pop. A blocking queue must first transfer the value out of the
protected FIFO and only then end the stored lifetime.

For copyable values/handles this contract is direct and sufficient for the
initial real-consumer shapes.

Move-only transfer is not rejected permanently. It is deferred until a
dedicated transfer primitive or lifetime proof exists.

## Allocation

Construction may allocate:

- RingBuffer backing storage;
- Mutex;
- Condition;
- runtime synchronization resources.

After successful construction:

- tryPush does not resize backing FIFO storage;
- waitPop does not resize backing FIFO storage;
- close does not resize backing FIFO storage.

Synchronization/runtime internals are measured separately from container
backing-storage allocation.

## Object lifetime — Stage 1

The queue is a reference type (`final class`), matching its synchronized
identity semantics.

Each worker that may access the queue must retain a normal class reference for
the duration of that access. Research explicitly qualifies that worker-held
references keep the queue alive after the initiating thread drops its own
reference.

No special destructor-driven waiter cancellation is promised. Explicit/manual
destruction while operations are active is outside the contract; ordinary D GC
reachability supplies lifetime instead of a bespoke synchronization protocol.

## Deterministic Stage-1 gates

1. empty wait blocks;
2. push wakes a waiter and delivers exactly one FIFO value;
3. full is distinct from closed;
4. close is idempotent;
5. close rejects future pushes;
6. close drains already queued values;
7. close wakes all blocked consumers;
8. synthetic notify-all without state change does not release waitPop;
9. multi-producer/multi-consumer exact accounting has no duplicate/lost value;
10. no backing FIFO allocation occurs during operations.

## Performance decomposition

Performance is split into two questions.

### Storage-layer overhead

Compare synchronized queue operations using RingBuffer storage with a manually
coded bounded ring under the same synchronization shape.

This asks whether containers-d composition itself costs material instructions.

### Qualified storage result

The storage-composition investigation initially reported a DMD 2.111 gap above
100%. That result was not a valid abstraction comparison:

- the manual ring used `(head + length) % capacity`;
- RingBuffer intentionally uses the previously qualified overflow-safe
  tail-room formulation;
- trivial runtime-ring clear still performed per-element pop work;
- imported/runtime owner access boundaries exposed additional DMD codegen cost.

M7 corrected the comparison and the implementation in evidence-driven steps:

1. retain the existing tail-room ring sequencing contract;
2. localize runtime storage access through the already-qualified typed mixin;
3. use a direct scalar push overload rather than generic `emplace`;
4. inline runtime status accessors and read package-internal owner capacity
   locally;
5. make `clear()` O(1) for trivial pointer-free T while preserving explicit
   lifetime/GC sanitation for other T;
6. compare the candidate with a manual ring using the **same tail-room
   sequencing algorithm**;
7. verify combined, push-only and pop-only checksums independently before
   measuring retired instructions.

Qualified x86_64 results for the fair comparison:

| Compiler | Combined | Push-only | Pop-only |
| --- | ---: | ---: | ---: |
| DMD 2.111 | +1.87% Ir | +2.55% Ir | -0.16% Ir |
| LDC 1.41 | -3.27% Ir | +0.07% Ir | -3.24% Ir |

Positive numbers mean RingBuffer-based candidate overhead versus the equivalent
manual tail-room ring; negative numbers mean the candidate executed fewer
retired instructions.

This places RingBuffer storage composition in the same performance class as the
manual implementation. M7 therefore does not justify a queue-specific storage
implementation or duplicating ring algorithms inside BlockingQueue.

The existing RingSequenceOps factoring probe independently shows exact
instruction parity between direct and factored tail-room sequencing on DMD and
LDC.

### Synchronization/contention

Stage 2 is active after storage parity qualified RingBuffer as the backing FIFO.

The contention probe compares the RingBuffer-backed queue with a direct manual
blocking queue under the same Mutex/Condition, close-and-drain, non-blocking
producer admission, and overflow-safe tail-room ring sequencing.

The first qualification matrix covers:

- capacities 1, 16, and 256;
- 1 producer / 1 consumer;
- 2 producers / 1 consumer;
- 1 producer / 2 consumers;
- 2 producers / 2 consumers;
- native Linux x86_64 with LDC 1.41;
- native Linux AArch64 with LDC 1.41.

Each run verifies exact count, sum, and xor accounting before accepting timing
data. Candidate/manual execution order alternates per sample and the reported
comparison is the median of paired candidate/manual ratios.

The initial gate is deliberately diagnostic: a paired-median candidate ratio
above 1.25 is considered materially off-class and stops the current design path
for investigation. Passing that guard is not yet a final performance claim.

Wall-clock contention is topology/scheduler sensitive and must not be confused
with storage abstraction cost. DMD remains a correctness/code-generation
control; LDC is the primary optimized performance compiler for this stage.

## Non-goals

- unbounded queue;
- producer blocking for capacity in Stage 1;
- priority queue;
- cancellation by event/task id;
- lock-free SPSC/MPSC/MPMC;
- DCanvas- or raster-specific types;
- consumer-repository migration.
