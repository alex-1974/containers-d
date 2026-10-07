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

## Destruction/lifetime rule — Stage 1

The queue object must outlive every thread that may call queue operations.

Research tests join all worker/waiter threads before releasing the last queue
reference.

Destruction with externally active operations is outside the admitted Stage-1
contract. M7 must decide whether a stronger production rule is required before
promotion.

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

### Synchronization/contention

Measure separately:

- 1 producer / 1 consumer;
- multiple producers / 1 consumer;
- multiple producers / multiple consumers.

Wall-clock contention is topology/scheduler sensitive and must not be confused
with storage abstraction cost.

## Non-goals

- unbounded queue;
- producer blocking for capacity in Stage 1;
- priority queue;
- cancellation by event/task id;
- lock-free SPSC/MPSC/MPMC;
- DCanvas- or raster-specific types;
- consumer-repository migration.
