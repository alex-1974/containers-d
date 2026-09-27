# Workspace buffer architecture research

Status: active research  
Tracking: issue #23

## Purpose

The next `containers-d` family must be selected from demonstrated consumer
requirements, not from a generic container checklist.

This document inventories buffer/container requirements across the current D
geospatial workspace and separates:

- generic reusable storage/container primitives;
- concurrency adapters and concurrent containers;
- domain-specific buffers that should remain in their owning library.

"Buffer" is used broadly here for storage that accumulates, stages, streams,
caches, queues, retains, or temporarily materializes data.

## Classification dimensions

Every candidate is evaluated by:

1. access pattern;
2. bounded versus growable capacity;
3. ownership and borrowing;
4. lifetime;
5. thread topology;
6. allocation behaviour;
7. contiguity and alignment;
8. cancellation/backpressure requirements;
9. element-lifetime complexity;
10. whether the abstraction is domain-independent.

## Consumer inventory

### dcanvas-dev

#### UI event queue

Current:
- `EventList` stores `CustomEvent` in `Collection`;
- push at back;
- ordinary get removes the front;
- cancel searches by unique ID and removes from the middle;
- access is mutex protected;
- background threads may post while the UI thread consumes.

Required shape:
- MPSC semantics;
- FIFO order;
- cancellation without O(n) element shifting;
- explicit close/shutdown semantics if generalized;
- boundedness/backpressure policy must be deliberate.

Likely destination:
- DCanvas-specific cancelable event queue;
- generic queue storage/concurrency primitives may come from `containers-d`.

#### Worker/socket command queue

Current `BlockingQueue!T`:
- mutex + condition;
- growable GC array;
- read/write positions;
- periodic compaction;
- blocking consumer.

Required shape:
- bounded blocking queue when a capacity contract is acceptable;
- segmented queue when unbounded growth is required;
- SPSC/MPSC specialization only where producer topology is proven.

#### Network receive

Current:
- reusable 64 KiB receive buffer;
- received slice is duplicated before callback handoff.

Required shape:
- owned byte blocks;
- transfer of ownership between producer and consumer;
- reusable size-class or fixed-block pool.

#### Network send

Required shape:
- queued variable-size byte chunks;
- partial-write cursor/offset;
- no requirement to concatenate all pending bytes;
- future scatter/gather compatibility.

#### Stream input/output

Current `LineStream` already uses explicit read and text buffers.

Required shapes:
- sliding contiguous read/decode buffer;
- linear write buffer with reserve/commit/flush;
- ring semantics are not automatically desirable because decoders often want
  contiguous spans.

#### Editor document

Current:
- `dstring[]` lines;
- line insertion/removal shifts following entries;
- edits create replacement character buffers;
- undo records retain copied text;
- syntax support may re-tokenize broadly.

Required shape:
- Piece Table/Piece Tree or comparable editor-specific storage;
- efficient arbitrary edits and line lookup;
- immutable add/original backing suitable for history sharing;
- incremental token/layout invalidation.

This is not a `containers-d` abstraction.

#### Render/frame staging

Current:
- heap `SceneItem` objects;
- `SceneItem[]`;
- OpenGLQueue Appenders for batches, vertices, colors, texture coordinates and
  indices;
- VBO/EBO creation/upload/destruction around flush.

Required shapes:
- frame arena;
- packed command buffer;
- grow-only frame staging buffers;
- GPU upload ring/multi-buffer staging;
- dirty-region buffer for software presentation.

These are graphics-domain abstractions, although generic arena/grow-buffer
primitives may be reusable.

#### Raster/scratch/caches

Current:
- `MallocBuf!ubyte/uint` raster backing;
- temporary full-image buffers for blur;
- reusable font measurement buffer;
- glyph/image caches and texture pages.

Required shapes:
- raster-domain aligned surface with stride;
- reusable raster scratch;
- SmallVector-like short temporary sequences;
- size-class pool for small glyph allocations;
- budgeted image/glyph caches;
- 2D texture-atlas allocator.

Raster/atlas/cache policy stays outside `containers-d`.

### geo-d

#### Douglas-Peucker workspace

Production simplification already exposes:
- caller-owned destination;
- caller-owned `size_t[]` traversal workspace;
- explicit workspace-size query;
- allocation-free execution.

This is a strong existing contract for caller-controlled scratch storage.

Potential generic support:
- `ScratchBuffer!size_t` convenience owner;
- no need to change the core caller-workspace API.

#### ExpansionBuffer

`geo.internal.expansion` contains `ExpansionBuffer!Capacity`:
- inline fixed-capacity storage;
- runtime logical length;
- clear;
- append;
- indexing;
- no allocation.

`geo3-d` independently contains the same fundamental shape.

This is direct evidence for research into:

`StaticVector!(T, Capacity)`

The exact-arithmetic modules may still keep a domain wrapper to preserve their
invariants and vocabulary.

#### Polygon validation

Connected-interior validation currently materializes temporary:
- contact records;
- union-find parent/rank arrays;
- per-contact marker arrays.

The operation explicitly documents temporary O(r + c) storage and is not
`@nogc`.

Potential future options:
- explicit caller workspace;
- reusable scratch buffer;
- operation-local arena.

Do not change the public allocation contract without a separate API decision.

#### Polygon union P1

The current draft P1 implementation deliberately uses many explicit internal
arrays for:
- boundary edges;
- exact events;
- atomic edges;
- arrangement vertices/edges;
- half edges and embedding tables;
- face/region labels;
- selected-edge traversal;
- cycles/components/canonical ordering;
- exact-to-materialized maps;
- materialized points/edges/ring offsets.

Most low-level helpers already accept caller-provided slices and are
allocation-free. The orchestration layer allocates the arrays.

This is strong evidence for:
- arena/scratch ownership;
- vectors/growable buffers;
- a sizing/planning phase where practical.

The immutable owning polygon-union result is a separate API/ownership concern
and must not be changed merely to adopt a container.

### geo3-d

Current buffer requirements mirror geo-d where the API family is shared.

Important evidence:
- independent `ExpansionBuffer!Capacity` implementation;
- shared Douglas-Peucker workspace sizing through `euclid-core-d`.

A generic `StaticVector` must preserve the allocation-free, stack/value
semantics required by exact predicates before either library adopts it.

### euclid-core-d

Current shared simplification code defines workspace sizing but owns no storage.

This reinforces the desired layering:

algorithm contract
-> caller workspace slice
-> optional generic owning scratch helper outside the mathematical core

### geodesy-d

Current geodesic and projection hot paths are intentionally allocation-free.

Examples:
- prepared geodesic solver retains small fixed coefficient arrays;
- direct/inverse operations use fixed local arrays;
- Transverse Mercator retains/precomputes bounded coefficient state.

Current conclusion:
- no generic owning buffer is required;
- fixed arrays are semantically appropriate;
- do not replace small compile-time-known numerical arrays with generic
  containers without measured benefit.

### quantities-d

Current production and active checked-conversion research are scalar/value
algorithms:
- `@safe pure nothrow @nogc`;
- fixed-width integer arithmetic;
- no variable workspace or owning buffer requirement.

Current conclusion:
- no immediate buffer/container consumer requirement.

### color-d

Production operations are predominantly allocation-free scalar/value transforms.

Tone-scale generation already accepts caller-provided output arrays.

Current conclusion:
- keep caller-owned output contract;
- a generic SmallVector may be convenient for applications, but color-d does
  not currently justify owning buffer machinery.

### osm-d

osm-d is already strongly buffer-oriented without owning generic containers in
the decoder hot path.

#### Borrowed wire cursors/ranges

- zero-copy `WireCursor`;
- borrowed tag, DenseNode, Way and Relation ranges;
- no per-element allocation;
- `@safe nothrow @nogc` hot paths where practical.

These should remain view/range abstractions, not containers.

#### StringTable workspace

`buildStringTableView` accepts caller-owned `StringRef[]` workspace and
returns an indexed borrowed view.

The documentation explicitly suggests block-arena storage.

#### Bounded decompression

`decodeBlobPayloadInto`:
- accepts caller-owned decompression storage;
- validates required output size;
- performs no D GC allocation;
- keeps raw payloads zero-copy.

ADR-0009 explicitly states that future streaming workers can use pooled
per-worker buffers.

This is direct evidence for:
- owned byte blocks;
- BufferPool / worker-local reusable buffers;
- explicit capacity and ownership transfer.

### raster-d

raster-d already has a sophisticated ownership and streaming architecture.

#### Retained physical resources

`OwnedByteResource`, `RasterBacking`, and `RasterLease` model:
- adopted external/raw resources;
- release callbacks;
- stable metadata tables;
- retained lifetime capabilities;
- borrowed read-only/writable views.

Do not replace this domain ownership model with `UniqueBuffer!T` blindly.
A generic owner may be useful as an implementation/input building block, but
raster resources deliberately support ownership provenance more general than a
single malloc-owned array.

#### Metadata storage

Raster construction currently creates stable heap copies of ResourceEntry and
PlaneDescriptor tables.

Potential research:
- whether a generic owning array primitive can simplify the implementation
  without weakening stable-address, failure, release, or lifetime contracts;
- whether small inline metadata tables are worthwhile for common one/few-plane
  rasters.

No migration without allocation/failure-path evidence.

#### Allocation-free execution

Core copy, conversion and reduction paths operate on provided views/resources
and allocate no execution storage.

This is already the desired hot-path model.

#### Region streaming and persistent workers

Research establishes:
- bounded active work;
- bounded materialization/compute stages;
- backpressure;
- reusable workers;
- deterministic shutdown.

The research-local `BoundedStageMailbox` is a concrete:
- fixed-capacity FIFO;
- mutex + condition;
- non-blocking producer admission;
- blocking consumer;
- close-and-drain queue.

Its slot/head/count implementation is effectively a bounded ring queue and is a
direct consumer case for a future generic blocking-queue layer built over
`RingBuffer` or equivalent storage.

### imagery-d

M2 source/cache/pipeline research explicitly requires:
- RAM budgets;
- decoded versus compressed caches;
- visible-region priority;
- cancellation;
- prefetching;
- progressive refinement;
- async source loading;
- reusable destination/workspace storage;
- bounded processing working sets.

Likely future domain structures:
- byte-budgeted source cache;
- decoded raster cache;
- priority/cancelable request queues;
- buffer pools;
- processing scratch arenas.

Cache/scheduling policy remains imagery-domain or application-domain.
Generic ownership/pool/queue primitives may come from `containers-d`.

## Cross-workspace candidate matrix

| Candidate | DCanvas | geo/geo3 | osm-d | raster-d | imagery-d | geodesy/quantities/color |
|---|---|---|---|---|---|---|
| StaticVector | strong small/scratch use | direct ExpansionBuffer analogue | weak | possible small metadata | possible metadata | weak |
| UniqueBuffer | MallocBuf replacement foundation | possible workspace owner | byte-block owner | possible implementation helper | likely source blocks | weak |
| Vector | broad | polygon-union orchestration/result helpers | owned-model future | metadata/task structures | metadata/request structures | weak |
| SmallVector | broad | small geometry/work arrays | possible tags/metadata sinks | small plane metadata candidate | request metadata | application convenience |
| ScratchBuffer | broad | simplification/topology/union | StringTable/decode workspace owner | operation/pipeline scratch | explicit M2 requirement | limited |
| Arena | frame/layout | polygon union | block workspace candidate | task/region materialization | pipeline operations | little current need |
| BufferPool | socket/network | limited | explicit decompression plan | worker resources | source/decode cache blocks | none |
| SegmentedQueue | worker/network | none | future streaming | possible scheduler | source scheduler | none |
| BlockingQueue | current direct need | none | future workers | direct mailbox analogue | async pipeline | none |
| SPSC/MPSC | direct event/worker need | none | future reader pipelines | persistent workers | async loading | none |
| MinHeap/PriorityQueue | timers | possible algorithms later | none current | scheduler possible | visible-region priority | none |

## Preliminary prioritization

This is a research order, not an API commitment.

### Tier A — strongest cross-workspace evidence

1. `StaticVector!(T, N)`
2. `UniqueBuffer!T`
3. `ScratchBuffer!T` and/or a narrowly scoped Arena foundation
4. `Vector!T` / `SmallVector!(T, N)`
5. bounded BlockingQueue semantics over existing ring storage

Rationale:
- StaticVector already has two real duplicate implementations.
- UniqueBuffer addresses repeated ownership/allocation machinery but must be
  designed against raster-d's more general resource model.
- Scratch/Arena requirements occur in DCanvas, geo-d, osm-d, raster-d and
  imagery-d.
- Vector/SmallVector have broad use but require a larger element-lifetime and
  growth contract.
- BlockingQueue has two concrete consumers: DCanvas and raster persistent-worker
  research.

### Tier B — after Tier A contracts

- BufferPool / owned byte blocks;
- SegmentedQueue;
- SPSC queue;
- MPSC queue;
- PriorityQueue/MinHeap.

These require more specialized lifetime, concurrency, scheduling, or recycling
contracts.

## Domain-specific boundaries

The following SHOULD NOT become generic `containers-d` types merely because
their names contain "buffer":

- PieceTree/PieceTable editor storage;
- RasterBuffer/RasterSurface;
- DamageRegionBuffer;
- frame render-command buffer;
- GPU upload ring;
- texture atlas allocator;
- image/decoded-data eviction policy;
- geospatial tile/cache policy.

## Research gates for any admitted generic primitive

Before production admission:

1. at least one concrete consumer contract;
2. ownership/copy/move semantics;
3. `.init` and empty-state semantics;
4. element lifetime/destructor semantics;
5. GC visibility for indirection-bearing element types;
6. alignment and checked-size rules;
7. allocation/failure behaviour;
8. `@safe` / `@trusted` boundary audit;
9. `@nogc` hot-path contract where applicable;
10. DIP1000 borrowing/escape tests when slices/references are exposed;
11. DMD 2.111 / LDC 1.41 baseline qualification;
12. adversarial correctness tests;
13. measured performance against the consumer baseline;
14. external consumer build;
15. portability/release-gate extension before stable release.

## Immediate next research issues

Issue #23 is the umbrella.

Separate follow-up issues should be opened for a candidate only after its
consumer contract is specific enough to state acceptance gates without guessing
the API.
