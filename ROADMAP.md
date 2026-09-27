# containers-d Roadmap

This repository follows the canonical workspace engineering contract under
`.workspace/`.

## M0 — Repository foundation

- establish repository structure;
- establish Fast CI and Release Gate;
- establish package and evidence boundaries;
- establish the first ring-buffer design contract.

## M1 — Ring-buffer semantic core

- define invariants;
- define element-lifetime semantics;
- define fixed versus runtime capacity;
- define overflow semantics;
- define observable allocation behaviour;
- define storage layout and alignment requirements;
- define safe access and mutation API;
- define wrapped-storage segment access;
- establish correctness and adversarial tests.

## M2 — Fixed-capacity ring buffer

- inline storage;
- compile-time capacity;
- no heap allocation;
- allocation-free steady-state operations;
- validate generated code and hot-path costs.

## M3 — Runtime-capacity ring buffer — complete

### M3.1 — Storage and ownership contract

- owning `RingBuffer!T` with runtime capacity;
- private aligned C-heap backend; no public allocator parameter initially;
- conditional GC-range registration for indirection-bearing `T`;
- inert capacity-zero `.init`;
- automatic copy disabled; O(1) ownership move;
- no backing-storage allocation during steady-state operations.

Contract: `docs/design/runtime-ring-buffer-storage.md`.

### M3.2 — Owning implementation

- explicit one-time storage acquisition;
- checked byte sizing and alignment;
- element-lifetime / GC-reachability correctness;
- move/destruction correctness;
- wrapped segment access;
- allocation and adversarial evidence.

### M3.3 — Runtime hot-path qualification — complete

- measured runtime wraparound strategies on DMD 2.111 and LDC 1.41;
- qualified representative push/pop/index/segment and mixed FIFO paths;
- retained the existing overflow-safe tail-room implementation;
- admitted no runtime specialization because no candidate improved the
  representative workload set without material regression or weaker semantics.

Evidence: `evidence/performance/runtime-ring-buffer-wraparound.md`.

M3 is complete.

## Release v0.1.0 — complete

- froze the first public ring-buffer family;
- resolved the release-relevant element-type contract for v0.1;
- aligned stable documentation with the admitted implementation;
- qualified the six-compiler release matrix;
- qualified Linux ARM64, Windows x64, macOS Intel and macOS ARM64 portability;
- verified the exported consumer archive;
- prepared the qualified state for promotion to `main` and annotated tag
  `v0.1.0`.

Tracking: issue #21.

## M4 — Workspace buffer architecture research — current

Tracking: issue #23.

The next production container family is not preselected. M4 derives the next
candidate from concrete consumers across DCanvas and the D geospatial workspace.

Research consumers include:

- `dcanvas-dev`: events, worker/network queues, stream buffers, editor
  storage, render/frame staging and scratch memory;
- `geo-d` / `geo3-d`: fixed-capacity expansion buffers, caller-owned
  simplification workspaces and geometry scratch;
- `osm-d`: zero-copy ranges, caller-owned StringTable/decompression
  workspaces and planned per-worker buffer pooling;
- `raster-d`: retained resource ownership, stable metadata storage, bounded
  pipeline/backpressure and persistent-worker mailboxes;
- `imagery-d`: RAM-budgeted source/cache/pipeline architecture;
- `geodesy-d`, `quantities-d`, and `color-d`: mostly allocation-free
  numerical paths that act as negative evidence against unnecessary generic
  storage.

Current candidate families include:

- `StaticVector!(T, N)`;
- `UniqueBuffer!T`;
- `Vector!T` / `SmallVector!(T, N)`;
- `ScratchBuffer!T` / Arena;
- BufferPool / owned byte blocks;
- SegmentedQueue / bounded BlockingQueue;
- separately researched SPSC/MPSC structures.

No candidate is admitted by this list alone.

Exit gate:

- workspace buffer architecture matrix complete;
- generic versus domain-specific boundaries recorded;
- concrete consumer contracts identified;
- candidate research priority established;
- the next implementation milestone admitted only with explicit correctness,
  ownership, safety and benchmark gates.

Research map:
`docs/research/workspace-buffer-architecture.md`.

## Later candidates

- FIFO queues;
- LIFO/FILO stacks;
- deque-like structures where justified;
- SPSC ring buffers;
- other bounded container primitives.

Later milestones are admitted only when their contracts and consumer need are
clear.
