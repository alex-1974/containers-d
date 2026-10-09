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
