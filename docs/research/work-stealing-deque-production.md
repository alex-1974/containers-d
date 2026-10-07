# Work-stealing deque production research

Status: active research  
Tracking: issues #38 and #39  
Superseded early contract draft: PR #40  
Source evidence: concurrency-d R0.1 P08e / P09-P16

## Ownership boundary

containers-d owns the reusable bounded single-owner / multi-thief deque family.

concurrency-d retains:

- Task / TaskRef / TaskRecord definitions;
- TaskRecord lifetime and reclamation;
- worker topology and victim selection;
- when to use single-item versus batch stealing;
- queue-full scheduler policy;
- executor coordination;
- parking/wake policy;
- cancellation and structured-concurrency semantics.

The deque transports values. It does not execute work or own referenced
scheduler objects.

## Selected algorithmic evidence

The source research selected the P08e marked-top bounded work-stealing deque.

Key properties:

- fixed power-of-two capacity;
- owner push/pop at the bottom;
- thieves steal from the top;
- bounded batch stealing through one marked-top reservation;
- 63-bit modular logical top domain plus one busy marker bit;
- cache-line separation of top and bottom state;
- no resize and no scheduler overflow action;
- native x86_64 and native AArch64 runtime qualification;
- explicit RC11 / code-generation / forced-overlap ordering evidence.

The Full64 distance-marker alternative is retained research but is not the
selected production direction because its state classification requires extra
bottom observation and showed material scheduler-hot-path cost.

## containers-d adaptation

The research prototype deliberately changes source shape without weakening the
qualified semantics.

### Capacity

The concurrency-d research type used:

```d
Deque!(T, LogSize)
```

The containers-d research type uses:

```d
ResearchWorkStealingDeque!(T, Capacity)
```

Capacity is the semantic quantity exposed to callers, matching the existing
containers-d style.

Current constraints:

- Capacity >= 2;
- Capacity is a power of two;
- 64-bit target;
- Capacity is at most 2^61, preserving the selected 63-bit counter-domain
  assumptions.

The eventual public type name remains an API-freeze decision.

### Element contract

P10/P16 establish a narrow category:

- trivial value transport;
- atomic shared slot load/store must compile;
- no destructor-owned queue element lifetime;
- no implicit pointee ownership;
- explicit shared-compatible indirections only;
- external objects referenced by handles remain externally owned.

Qualified examples include:

- ulong;
- one-word trivial handles;
- 128-bit trivial pairs;
- shared-compatible pointer handles.

Rejected examples include:

- ordinary unshared pointer elements;
- GC class references;
- destructor-owning values;
- non-trivial copy/postblit representations.

The prototype exposes a research predicate:

```d
isWorkStealingTransportElement!T
```

only to qualify positive and negative compile cases. It is not yet a public API
promise.

### Safety boundary

P11 qualified the normal callable operations as:

```text
@safe @nogc nothrow
```

The selected narrow trusted boundary is the sequentially-consistent barrier
helper. The whole deque operation is not trusted.

Concurrent identity is non-copyable.

Language memory safety does not prove the protocol condition:

```text
exactly one owner
zero or more thieves
```

Owner-only operations and thief-safe operations must therefore be documented
separately.

## Prototype stage

The current containers-d prototype already carries:

- direct Capacity contract;
- power-of-two constraint;
- 63-bit marked-top state representation;
- owner tryPush;
- owner pop;
- thief steal;
- thief stealBatch into caller-owned output;
- non-copyable identity;
- @safe @nogc nothrow callable operations;
- narrow trusted barrier helper;
- positive/negative T capability probes;
- sequential LIFO/FIFO semantics;
- full behavior;
- slot reuse;
- near-counter-wrap slot selection.

It is intentionally not package-root exported.

## Next correctness gates

Before production promotion reproduce the R0.1 concurrency evidence in
containers-d:

1. exact last-item owner/thief race;
2. exact multi-thief accounting with duplicate/missing detection;
3. deterministic owner/batch marked-top overlap;
4. bounded near-capacity concurrent refill;
5. 63-bit counter wrap qualification;
6. caller-buffer batch ordering;
7. @safe compile probes from an external consumer;
8. non-copyability/assignment/pass-by-value negative compile tests.

## Architecture gates

Native runtime qualification must include:

- Linux x86_64;
- Linux AArch64.

Cross-compilation alone is not sufficient for the memory-ordering contract.

DMD 2.111 remains the correctness/development baseline. LDC 1.41 remains the
optimized-performance baseline.

## Performance gates

The containers-d implementation must remain in the same performance class as
the retained P08e evidence.

Required measurements include:

- owner tryPush;
- owner pop;
- push/pop pair;
- empty steal;
- successful steal;
- one owner + one thief;
- multiple thieves;
- batch steal;
- near-capacity operation;
- scheduler-neighbourhood distributed production;
- fine / medium / coarse tasks;
- recursive and irregular task graphs.

Taskflow is evidence, not the specification. Comparisons must remain
semantically fair.

Batch stealing remains a primitive, not a policy. R0.1 showed that it regresses
some extremely small-task workloads and helps when synchronization can be
amortized.

## Promotion rule

The research module remains internal until:

- the generic T contract is stable;
- correctness and ordering evidence is reproduced;
- x86_64 and AArch64 runtime gates pass;
- the public API audit is complete;
- performance and consumer-neighbourhood qualification pass.

Only then should a clean production promotion expose the family.
