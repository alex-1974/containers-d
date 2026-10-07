# M4.5 — real-consumer adaptation proofs

Status: active research  
Tracking: issue #49  
Parent architecture: issue #23  
Baseline: post-M4.4 `develop`

## Purpose

M4.5 tests whether the internal family model can serve materially different
consumers without exposing a universal container template.

The required proof is architectural rather than migratory: consumer repositories
are evidence sources, not write targets. A consumer changes only after a later
family-specific promotion and acceptance gate.

## Adaptation matrix

| Consumer class | Representative evidence | Access pattern | Ownership / lifetime | Allocation | Thread topology | Capacity | Failure / backpressure | containers-d fit | Decision |
|---|---|---|---|---|---|---|---|---|---|
| Numeric caller-owned workspace | geo-d / geo3-d expansion buffers; Douglas-Peucker workspace; geometry validation scratch | contiguous append/index, short-lived work arrays | caller or domain wrapper owns lifetime | often none in hot path | single-threaded | compile-time fixed or caller-sized | precondition / explicit workspace sizing | `StaticVector` is a direct primitive only for fixed-capacity variable-length storage; raw slices remain valid API for caller-workspace algorithms | compose or wrap; do not force ownership into the algorithm |
| Synchronized bounded mailbox | raster-d BoundedStageMailbox; DCanvas worker/blocking FIFO need | FIFO push/pop, wait/wake, close/drain | mailbox owns queued values; synchronization owns waiter lifetime | one-time queue storage acceptable; no operation-time backing growth | producer/consumer synchronization required | explicitly bounded for raster case | full result, blocking empty consumer, close/drain/wake semantics | `RingBuffer` can be storage below a distinct synchronization family, but cannot itself gain thread-safety policy | future `BlockingQueue`/mailbox family; keep RingBuffer single-threaded |
| Reusable contiguous scratch | osm-d decompression output / StringTable workspace; raster/imagery reusable workspace; DCanvas scratch | contiguous temporary storage reused across calls | worker/request owner retains capacity; borrowed slices handed to algorithm | growth or establishment phase may allocate; reuse phase should not | usually thread-confined | runtime capacity / high-water driven | explicit insufficient-capacity or controlled growth | current RingBuffer/StaticVector are not semantic matches; M4.2 storage/lifetime machinery may be reusable internally | future narrow `ScratchBuffer`; keep algorithm APIs slice-based |
| Cross-thread pooled blocks | planned OSM per-worker decompression buffers; network byte blocks; imagery/raster worker resources | acquire block, use, return/recycle | pool owns idle blocks; borrower temporarily owns/leases block | pool establishment/replenishment | cross-thread or worker-local depending design | size class / block count boundedness is policy | empty-pool behavior, blocking/nonblocking, reclamation | not a ScratchBuffer mode and not UniqueBuffer alone | separate BufferPool/owned-block family only if contract is proven |
| Heterogeneous arena | frame/layout/topology/request scratch candidates | bump allocation, bulk reset | arena owns heterogeneous allocations until reset | chunk allocation outside hot subphase where possible | normally thread-confined | chunk/high-water based | exhaustion/growth policy explicit | not interchangeable with reusable typed buffer | separate Arena family if real consumers justify it |
| Domain-specific retained resources | raster OwnedByteResource/RasterBacking/RasterLease; editor PieceTree; GPU upload ring; caches | domain-specific | richer provenance, callbacks, retention or policy | domain-defined | domain-defined | domain-defined | domain-defined | generic primitives may be implementation components only | remain in consumer library |

## Proof A — fixed-capacity numeric adaptation

### Existing semantic match

The already-qualified `StaticVector!(T, Capacity)` covers the repeated shape:

- inline storage;
- compile-time capacity;
- runtime logical length;
- append/index/clear;
- no backing allocation.

This is sufficient as a generic primitive below a geometry-specific wrapper when
the wrapper preserves domain invariants and names.

### Important negative result

Caller-workspace algorithms such as simplification do **not** become better by
owning their storage. Their current contract:

```text
algorithm
-> caller-provided slice/workspace
-> optional owner supplied by application
```

is the more general and more allocation-transparent API.

Therefore M4.5 treats raw/caller slices as a first-class successful adaptation,
not as evidence that every consumer must import a container type.

## Proof B — synchronized bounded mailbox adaptation

A bounded mailbox has semantics absent from RingBuffer:

- synchronization;
- blocking wait;
- wakeup;
- close;
- close-and-drain;
- producer admission outcome;
- waiter destruction/shutdown rules.

Those semantics are observable and therefore define a separate public family.

The correct layering remains:

```text
BlockingQueue / mailbox
    synchronization + close/wake protocol
    bounded FIFO storage
        RingBuffer-like mechanics
```

The storage primitive may reuse internal sequencing/lifetime machinery, but
`RingBuffer` itself remains single-threaded.

Rejected designs:

- `RingBuffer!(T, threadSafe = true)`;
- synchronization policy template parameters on RingBuffer;
- a generic queue mode enum selecting blocking/nonblocking/concurrent behavior.

## Proof C — reusable and pool-backed storage adaptation

Three ownership models must stay distinct.

### ScratchBuffer

One reusable contiguous typed region:

- one logical owner;
- capacity retained between calls;
- borrowed slice supplied to an existing algorithm;
- optional controlled growth before/around hot execution;
- reset changes logical use, not ownership.

This is the closest candidate for OSM decoder workspace, geometry orchestration
scratch, raster/imagery work buffers and DCanvas temporary buffers.

### Arena

Heterogeneous or multi-allocation request/frame lifetime:

- bump/chunk allocation;
- bulk reset;
- destructor/alignment policy differs from one typed buffer;
- invalidation model is broader.

It is not a ScratchBuffer configuration switch.

### BufferPool

Multiple reusable owned blocks:

- acquire/release or lease semantics;
- potentially cross-thread;
- idle-resource ownership belongs to the pool;
- empty-pool/backpressure policy is observable.

It is not an Arena or ScratchBuffer flag.

## Internal reuse versus public customization

M4.2 and M4.4 establish useful package-internal mechanisms:

- element lifetime capability classification;
- placement move / end-lifetime typed mixins;
- structural raw-slot contracts;
- inline-storage machinery;
- ring sequencing machinery.

M4.5 finds no evidence that these mechanisms should become public policies.

Consumers need different **types and semantic contracts**, not arbitrary
combinations of implementation mechanisms.

## M4.5 conclusion

The three required adaptation modes are feasible without a universal public
container framework:

1. **domain wrapper / caller workspace**
   - use StaticVector only where semantics match;
   - keep slice-based numerical APIs where caller ownership is intentional.

2. **composition into a distinct synchronized family**
   - bounded FIFO storage can underlie a future BlockingQueue;
   - synchronization, close/drain and wake semantics define the public family.

3. **ownership-specific reusable storage families**
   - ScratchBuffer, Arena and BufferPool are distinct candidates;
   - do not collapse them into one storage-policy template.

## Recommendation for M4.6

Do **not** expose an advanced public customization API now.

Evidence supports:

- concrete public families with narrow semantics;
- package-internal compile-time composition;
- domain wrappers/adapters where domain vocabulary matters;
- automatic compiler/architecture selection hidden from consumers.

A public customization mechanism should be reconsidered only when at least two
real consumers require the same semantic family with materially different
storage/backend choices that cannot be handled source-compatibly through
private implementation selection or wrappers.

The M4.5 evidence therefore favors:

```text
family tree
+ internal mechanisms
+ domain composition
```

over:

```text
Container!(
    StoragePolicy,
    GrowthPolicy,
    ConcurrencyPolicy,
    OwnershipPolicy,
    ...)
```

## Follow-on family research

The evidence keeps these as separate trackers:

- #26 — UniqueBuffer / narrow owned contiguous storage;
- #27 — ScratchBuffer / Arena;
- #28 — bounded BlockingQueue;
- #38 / #39 — work-stealing deque promotion for concurrency-d.

Their order is consumer-driven and does not imply they share one public policy
framework.