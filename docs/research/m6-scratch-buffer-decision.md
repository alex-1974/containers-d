# M6 ScratchBuffer decision

Status: research complete  
Tracking: issue #27  
Evidence PR: #58

## Decision

Admit a production `ScratchBuffer!T` family.

Do **not** admit a public `UniqueBuffer!T` foundation at this time.

Do **not** fold Arena, BufferPool, live reallocation, pooling or custom release
provenance into ScratchBuffer.

## Qualified ScratchBuffer contract

The qualified semantic core is:

- one uniquely owned contiguous typed backing allocation;
- inert `.init`;
- runtime capacity;
- exact live contiguous prefix;
- borrowed live slice;
- explicit append with full result and no hidden growth;
- `reset()` ends live lifetimes but retains capacity;
- trivial pointer-free reset specializes to O(1);
- whole-owner move transfers storage without relocating live elements;
- empty-only `tryReserve(minCapacity)` can increase capacity between work
  phases;
- reserve never moves/copies live T;
- already-sufficient reserve is a no-op even with live contents;
- no automatic shrink;
- no geometric growth policy;
- first family is thread-confined.

## Internal ownership conclusion

M6 initially asked whether ScratchBuffer required a generic public UniqueBuffer
foundation.

It does not.

The already-qualified package-internal mechanisms are sufficient:

- `RuntimeStorageOwner!T` owns aligned runtime storage and GC registration;
- `RuntimeStorageAccessOps!T` generates slot/slice access in the consuming
  module so DMD does not pay imported-helper hot-path cost;
- element lifetime mixins provide placement move and end-lifetime behavior.

This split keeps ownership machinery private while exposing a concrete semantic
family.

A future public UniqueBuffer should be reconsidered only if at least two public
families/consumers require direct ownership transfer of a contiguous block as
their **observable** contract rather than merely as an implementation detail.

## Performance evidence

### Repeated retained-capacity reuse

Manual baseline: one preallocated contiguous array + logical length.

Final qualified DMD 2.111 result:

```text
manual    13,434,905 Ir
candidate 13,434,905 Ir
delta      0
```

Normalized DMD wrapper size:

```text
manual    50 instructions
candidate 50 instructions
```

LDC 1.41 generates equal optimized wrapper code.

The path to parity was evidence-driven:

1. generic reset originally performed unnecessary per-slot work for trivial T;
2. compile-time lifetime/indirection specialization made trivial reset O(1);
3. DMD still exposed imported runtime-storage accessor cost;
4. `RuntimeStorageAccessOps!T` moved pointer arithmetic/sanitation into the
   consuming aggregate;
5. final DMD retired instructions reached exact parity.

Existing Runtime RingBuffer operation and wraparound probes remain green after
the internal storage-access factoring.

### Representative consumer shapes

All profiles are containers-d-side semantic models. Consumer repositories were
not modified.

| Profile | DMD 2.111 candidate vs manual | LDC 1.41 |
| --- | ---: | ---: |
| DCanvas-like small trivial-struct scratch | -7.30% Ir | 0.00% |
| Geometry-like point workspace + borrowed slice algorithm | +2.93% Ir | 0.00% |
| OSM/Raster-like large reusable byte workspace | -0.57% Ir | 0.00% |

Each candidate/manual pair produces an identical non-trivial checksum.

These results place ScratchBuffer in the same performance class as direct
manual owner+length implementations for the qualified workloads.

## Empty-only capacity establishment

Stage 2 qualifies:

```d
bool tryReserve(size_t minCapacity);
```

Semantics:

- returns true without mutation when current capacity is already sufficient;
- returns false without allocation/mutation when growth is required while live
  elements exist;
- when empty, replaces backing storage with exactly minCapacity slots;
- allocation failure follows the existing fatal OOM contract;
- successful growth invalidates previous borrows;
- no live T is copied or moved.

Tests cover allocation/release accounting, over-aligned T and
indirection-bearing T across storage replacement.

This is sufficient for the represented high-water/reuse model without
introducing vector-like live growth.

## High-water accounting

`highWater` was useful research telemetry and incurs no material cost in the
qualified profiles.

For the first production API it remains a candidate rather than an essential
semantic primitive. Production promotion should include it only if its
caller-facing value outweighs the extra persistent state/API surface.

The core ScratchBuffer contract does not depend on it.

## Rejected/deferred directions

### Public UniqueBuffer

Deferred.

Current evidence shows it would be an implementation abstraction rather than a
distinct consumer semantic requirement.

Tracker #26 may be closed as not currently justified; retained ownership
research remains valid evidence.

### Live reallocation

Deferred.

No qualified representative workload requires preserving live contents while
capacity grows. Empty-only reserve avoids relocation, exception/failure
rollback, self-referential move and borrow-invalidation complexity.

### Arena

Separate family.

Heterogeneous/chunk/bump allocation and bulk reset have different lifetime and
alignment semantics.

### BufferPool

Separate family.

Pool ownership, acquire/release/lease, cross-thread transfer and empty-pool
backpressure are observable semantics absent from ScratchBuffer.

## Production promotion requirements

A clean production branch from current develop should carry only:

- public `containers.scratch_buffer` module;
- package-root `ScratchBuffer` export;
- the minimal package-internal runtime-storage access factoring required for
  zero-cost DMD codegen;
- correctness/lifetime/alignment/GC/DIP1000 tests;
- external package-root/archive consumer;
- retained-capacity and representative-profile performance gates;
- DMD/LDC controlled compiler matrix and platform gates;
- Ddoc/API documentation.

The research branch/PR remains preserved and is not merged wholesale.
