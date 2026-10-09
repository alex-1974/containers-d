# M9 candidate: Arena — source-backed consumer contract audit

Status: research only; **not** API admission  
Date: 2026-10-09  
Tracking: #81  
Branch: `research/m9-arena-consumer-contract`

## Decision so far

**Do not introduce `Arena` in production yet.** An arena is a distinct
ownership/lifetime family, but the inspected OSM decoding APIs already separate
the algorithm from its workspace owner by accepting typed caller-owned slices.
That is an intentional, successful contract and must not be replaced.

The current evidence supports a *potential* worker-local allocation mechanism,
not yet a cross-consumer generic arena.

## Sources and confidence

Source-level inspection (remote default branches, 2026-10-09):

- [osm-d decompression](https://github.com/alex-1974/osm-d/blob/main/source/osm/io/pbf/decompress.d):
  `decodeBlobPayloadInto(BlobView, ubyte[] outputBuffer, ...)` requires
  caller-owned output with capacity at least `rawSize` for zlib. Raw payload
  uses zero-copy borrowed Blob storage. Decoding does not own the buffer.
- [osm-d string table](https://github.com/alex-1974/osm-d/blob/main/source/osm/io/pbf/string_table.d):
  `buildStringTableView(..., StringRef[] workspace, ...)` fills preallocated
  index space. `StringTableView.entries` borrows workspace; `rawBlock`
  borrows input. Both must survive the view's use.
- [raster-d resource metadata](https://github.com/alex-1974/raster-d/blob/develop/source/raster/resource.d):
  `ResourceEntry` has a base, byte length, opaque release context/callback,
  and positive access provenance; a release context must outlive retention.
  This is **not** merely a generic arena allocation.
- [osm-d architecture](https://github.com/alex-1974/osm-d/blob/main/ARCHITECTURE.md):
  design describes worker-local block arena, but this document is a design
  statement, **not** evidence that the arena is implemented.
- [osm-d performance contract](https://github.com/alex-1974/osm-d/blob/main/docs/PERFORMANCE.md):
  specifies worker-local block arena, O(1) reset intent, bounded memory and
  no GC allocation per element; these are goals until verified against code.
- [imagery-d roadmap](https://github.com/alex-1974/imagery-d/blob/develop/ROADMAP.md):
  source/cache research accepted, first production vertical slice remains
  pending. Do not count its planned cache as a working arena consumer.
- [containers-d M4.5](../../docs/research/m4-5-consumer-adaptation.md):
  earlier candidate inventory; caller-owned slices are already a valid
  outcome, and ScratchBuffer, Arena and BufferPool must remain distinct.

The available connector did not enumerate whole consumer source trees or
return code-search matches. This audit therefore has **positive evidence for
the explicit modules above**, but cannot claim that no other arena code exists.

## A concrete observed OSM lifecycle

```text
caller owns decompression output (ubyte[])
     -> decodeBlobPayloadInto
     -> BlobPayloadView borrows either raw Blob or output
     -> decodePrimitiveBlockLayout
     -> caller owns StringRef[] index storage
     -> buildStringTableView
     -> StringTableView borrows original block + index storage
     -> consumers finish
     -> both backing lifetimes may end or capacity may be reused
```

A single `ScratchBuffer!StringRef` or fixed/caller-provided `StringRef[]`
can satisfy this specific index workload. Combining decompression bytes and
indices in an arena is not automatically better: their storage/borrowing
semantics and alignment differ. The existing `ScratchBuffer` retains capacity
without relocating live elements, so it must be the comparison baseline.

## Arena-specific questions requiring actual experimental proof

1. **Allocs:** At least two *simultaneously live* heterogeneous allocations
   within one reset epoch, beyond typed index/output slices. Otherwise no
   independent arena family is established.
2. **Reset:** Does O(1) reset apply only to trivially destructible payloads?
   For nontrivial T, correct destruction is at least O(number of live T).
   Reject the unqualified claim that all arenas can reset in O(1).
3. **Alignment:** Checked `alignUp`, overflow-safe allocation size and
   over-aligned values; no invalid pointer arithmetic.
4. **Borrowing:** A returned slice/pointer must not survive reset, growth,
   destruction or a move that invalidates backing; D `@safe` alone may not
   statically forbid every escape. Any `@trusted` interface requires an
   explicit proof.
5. **Growth:** Fix one contract before benchmarking: no growth, segmented
   chunks with stable prior addresses, or relocating contiguous storage.
   Relocation is incompatible with already-issued borrowed views.
6. **Failure:** Explicit exhausted/too-large/overflow result; do not use
   `assert` as public input validation.
7. **GC references:** Ensure reachable pointers in arena-owned objects remain
   visible to D's GC when backing lives outside the GC heap, or restrict the
   element contract with evidence.
8. **Threading:** Worker-confined arena first. No hidden locks, thread-safety
   claims or cross-thread reset.
9. **Reset poisoning:** Diagnostic canaries should detect stale views where
   feasible; poisoning is not a substitute for an enforceable safe contract.
10. **Resource provenance:** Do not fold raster-d external release callback
    ownership into an arena. Such resources have independent destruction and
    access provenance.

## Candidate experiment design (not yet implemented)

Compare three implementations on **the same output and validation work**:

- caller-sized typed slices / existing worker storage;
- `ScratchBuffer!T` for the index region;
- internal experimental chunked arena, with typed aligned allocations and
  explicit epoch reset.

Required workloads:

| Case | Payload | Why |
|---|---|---|
| OSM string index | `StringRef[N]`, no other live allocation | negative control: should not need Arena |
| Heterogeneous block metadata | interleaved aligned `StringRef` + segment records with overlapping lifetimes | potential Arena advantage |
| Many tiny temporary records | multiple allocations per block, bulk reset | characterize allocation overhead |
| Nontrivial destructor | live values with destruction counters | establish exactly-once end-lifetime |
| Alignment | alignments including over-aligned, chunk boundary | correctness |
| Capacity/failure | zero capacity, exhaustion, overflow, late growth | failure semantics |
| Borrow lifetime | old references across reset/growth | safety limitation demonstration |

Benchmark DMD 2.111 and LDC 1.41 release-equivalent settings and supported
newer toolchains where relevant. Record platform, compiler/flags, allocation
counts, median latency, high-water memory, p95 where useful, and semantic
preflight. For fair C++ reference use analogous monotonic resource/pool
behavior with matching construction/destruction, validation and allocation.

## Admission criteria

Only propose a production M9 Arena if:

- current source proves real heterogeneous multi-allocation demand;
- at least one further independent consumer exhibits the same semantics
  (or a formally justified exception is recorded);
- the `@safe` borrowing/reset/lifetime model is viable;
- a narrow API is superior to slices + ScratchBuffer in representative work;
- DMD/LDC correctness, allocation and C++-comparable performance gates pass;
- an ADR records the choice and non-goals.

**Otherwise: defer.** No change to consumer code, public API or release plan.


## Second consumer — geo-d polygon union (new source-level finding)

Inspected `geo-d` default `develop`, module
[`source/geo/internal/polygon_union_p1.d`](https://github.com/alex-1974/geo-d/blob/develop/source/geo/internal/polygon_union_p1.d)
(lines approximately 190–395).

The production polygon-union orchestration **actually allocates many
simultaneously live heterogeneous arrays** within one call:

| Scratch role | Type | Allocation cardinality |
|---|---|---|
| selected half-edges | `bool[]` | `halfEdgeCount` |
| successor, edge cycles | `size_t[]` each | `halfEdgeCount` each |
| vertex cycle | `size_t[]` | `vertexCount` |
| cycle records | `ExactUnionBoundaryCycle[]` | `halfEdgeCount` |
| cycle roles / component maps | `ExactUnionCycleRole[]` / `size_t[]` | `cycleCount` |
| component descriptors | `ExactUnionComponent[]` | `cycleCount` |
| layout and canonical ordering | multiple `size_t[]` | `cycleCount`, `componentCount`, `componentCount+1` |
| materialization working state | `size_t[]`, `Point2!double[]`, `MaterializedUnionBoundaryEdge[]` | vertex and half-edge bounds |

The arrays are used together across successive internal routines, with
separate explicit slices passed into the algorithms. This is a *real*
heterogeneous multi-allocation consumer and cannot be reduced to one
`ScratchBuffer!T` without losing typed separation.

**Critical ownership boundary:** Some arrays later contribute to output
materialization. The public polygon-union result is immutable owning
GC-backed storage
([`geo.polygon_union`](https://github.com/alex-1974/geo-d/blob/develop/source/geo/polygon_union.d)).
No arena-backed references may escape into such retained results. The
working-set classification must follow actual data flow, not merely the
`new T[]` syntax.

The implementation currently uses D GC arrays and does **not** demand a new
`@nogc` caller-facing API. An arena would be an **optional, measured
internal allocation optimization**, not a source-compatible drop-in migration.

### Updated admission assessment

- Two **independent semantic consumers** are now identified:
  `osm-d` documented worker-local block-lifetime heterogeneous scratch;
  `geo-d` observed in-source many typed allocations per union call.
- Their **implementation maturity differs**: `geo-d` is directly observed;
  `osm-d` still needs proof of an implemented multi-allocation arena path.
- Sufficient reason exists for a **restricted research-only arena prototype**,
  **not** production/public M9 admission.

### Constrained prototype hypothesis

Research a *worker-/call-confined, monotonic, segmented, byte-backed arena*
with bulk reset for **trivially destructible / pointer-free payloads only**.
Expose typed allocation as a tested research convenience, but avoid promising
compile-time non-escaping borrows until proved.

- Do not relocate chunks while borrows exist.
- All size arithmetic checked; alignment explicit and tested.
- No GC references in externally malloc-backed allocations unless registered
  and proven; initial prototype instead rejects GC-indirection-bearing types.
- Record exhaustion and high-water explicitly.
- Never reset before output materialization has copied needed data.
- Separate layout growth/allocation costs from steady-state per-call costs.
- Benchmark many independent `new T[]` arrays (real baseline), reused
  `ScratchBuffer` or caller slices where practicable, and monotonic arena.
- Require measurable improvement on *both* typed-array setup cost and complete
  polygon-union throughput; benchmark overhead alone is insufficient.

### Prototype exit gate

A candidate implementation is worth *researching* now, but it must remain
non-public until compiler-checked lifetime tests, source-level call-site
audit, DMD/LDC performance, fair C++ comparator and an ADR are available.
The repo's active pre-migration/research workflow must be preserved.


## 2026-10-09 — Research redirection: existing Phobos region allocators

**Decision: PAUSE custom FixedArena development.** The user's XPS v9 experiment
reported `constructions=1 logical_releases=1` for both DMD and LDC, but that
only covers one return-by-value path and does not establish generalized
ownership transfer or safe reset.

The official D Phobos library already includes:
- `std.experimental.allocator.building_blocks.region.Region!ParentAllocator`:
  owned contiguous monotonic storage; `deallocateAll`; reports exhaustion.
- `BorrowedRegion`: caller-backed, non-owning region. This is a promising
  fit for existing slice-owned consumer workspaces.
- `InSituRegion!(size, alignment)`: inline static storage; beware documented
  alignment overhead reducing usable capacity.
- `std.experimental.allocator.building_blocks.allocator_list.AllocatorList`:
  factory-created region chains, with independently selectable bookkeeping
  allocator. Do **not** assume no GC bookkeeping or guaranteed stable addresses
  without source tests.

Official sources:
- https://dlang.org/phobos/std_experimental_allocator_building_blocks_region.html
- https://dlang.org/phobos/std_experimental_allocator_building_blocks_allocator_list.html
- https://dlang.org/phobos/std_experimental_allocator.html

### Qualified observations vs outstanding hypotheses

*Documented*: the region types offer bump allocation, alignment,
`deallocateAll`, and owned/borrowed/in-situ storage alternatives.
*Not yet compiler-qualified on our supported versions*: copy/move owner
invariants, exact alignment/overflow behavior for all capacities,
GC-reachable pointers, destructor obligations, lifetime safety across reset,
and `AllocatorList` full-reuse semantics.

The production API remains unchanged; `FixedArena` is a historical research
control, not the next planned implementation.

### Next experimental matrix

1. DMD 2.111.0 and LDC 1.41.0: compile/run bare Region, BorrowedRegion,
   InSituRegion allocation/reset/alignment probes. Record exact Phobos versions.
2. Read the corresponding Phobos source, including destructor, copy/move and
   release logic; negative compile probes must reject unsafe owner copying.
3. Independently test `AllocatorList` and bookkeeping allocation behavior;
   do not conflate `deallocateAll` with release of retained backing chunks.
4. Compare against `ScratchBuffer`, caller slices, and C++
   `std::pmr::monotonic_buffer_resource` under matching capacity,
   allocation failure, destructor and reset semantics.
5. Only after that investigate complete geo-d polygon union and osm-d block
   throughput; public M9 Arena still requires measured cross-consumer benefit.

**Safety rule:** Do not expose `@safe` arena borrows or silently reset active
views. DIP1000 escape tests alone do not prove safe arena reset.
