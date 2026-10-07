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

- released the first public ring-buffer family;
- qualified the six-compiler and cross-platform release matrix;
- verified the exported consumer archive;
- published annotated tag `v0.1.0`.

Tracking: issue #21.

## Release v0.1.1 — complete

- corrected StaticRingBuffer over-aligned element placement on affected
  compiler/target combinations;
- preserved the ordinary-alignment hot path;
- added over-alignment GC reachability and D-vs-C++ performance qualification;
- qualified the full release matrix and exported package;
- published signed annotated tag `v0.1.1`.

Tracking: issues #31 and #32.

## M4 — Consumer-driven container-family architecture — complete

Tracking: issue #23.

M4 derives reusable families from concrete workspace consumers rather than
generalizing the ring buffer into a universal policy container.

### M4.1 — Family model and invariants — complete research

- classify storage/access/lifetime/ownership/thread-topology needs;
- separate family semantics from reusable internal machinery;
- keep materially different semantics as distinct public types;
- preserve consumer-owned domain vocabulary where a wrapper would add cost.

Research evidence remains on its original branches/PRs.

### M4.2 — Internal lifetime/storage foundation — complete

Tracking: issue #29. Promotion: PR #43.

- package-internal element capability/lifetime classification;
- typed template mixins for placement move and lifetime end;
- structural raw-slot and reusable-slot storage contracts;
- package-internal inline-storage proof;
- zero-overhead qualification on DMD 2.111 and LDC 1.41;
- no public customization API and no change to released ring semantics.

### M4.3 — StaticVector proof and production promotion — complete

Tracking: issues #25 and #34. Research proof: PR #33. Promotion: PR #44.

Qualified research evidence:

- fixed-capacity contiguous mechanics against geo-d/geo3-d ExpansionBuffer
  baselines;
- representative expansion-algorithm qualification;
- real geo-d and geo3-d consumer proofs;
- DMD hot paths instruction-identical to the consumer-local form where
  compile-time composition is used;
- lifecycle, GC, over-alignment, borrow and adversarial correctness evidence;
- build/code-size qualification.

Production promotion admits only the stable `StaticVector!(T, Capacity)` type.
The research-only scalar composition mixin remains outside the compatibility
surface.

### M4.4 — Ring family factoring — complete

Tracking: issue #45. Research proof: PR #46. Promotion: PR #47.

Qualified evidence:

- common head/length sequencing isolated without sharing storage or ownership;
- static power-of-two, static non-power-of-two and runtime sequencing are
  instruction-identical before/after factoring on DMD 2.111 and LDC 1.41;
- actual StaticRingBuffer normal and over-aligned production workloads are
  instruction-identical to develop;
- actual RingBuffer index, push/pop, segment and mixed workloads are
  instruction-identical at capacities 63 and 64 on both baseline compilers;
- layout, Fast CI, GC, DIP1000, lifetime and existing runtime performance gates
  remain qualified.

Production promotion is deliberately limited to the package-internal
`RingSequenceOps` typed mixin. StaticRingBuffer and RingBuffer retain their
separate storage, ownership, allocation, copy/move and public semantic
contracts.

### M4.5 — Real-consumer adaptation proofs — research complete

Tracking: issue #49.

Qualified adaptation modes:

- numeric/domain-owned workspaces use StaticVector only where its semantics
  match; caller-owned slice APIs remain first-class where ownership belongs to
  the caller;
- synchronized bounded mailboxes are a separate semantic family layered over
  bounded FIFO storage, not a thread-safety mode of RingBuffer;
- reusable contiguous scratch, heterogeneous arenas and cross-thread buffer
  pools are distinct ownership/lifetime families rather than storage-policy
  switches.

The M4.5 evidence finds no need for a universal public customization surface.
See `docs/research/m4-5-consumer-adaptation.md`.

### M4.6 — Public customization decision — complete

Tracking: issue #52.

Decision:

- no advanced public customization/policy framework is exposed;
- concrete semantic families remain the public API;
- templates, traits, static if, typed mixins and compiler/architecture
  capability selection remain package-internal implementation mechanisms;
- public customization may be reconsidered only after multiple real consumers
  require the same semantic family with incompatible private backend needs and
  the diagnostics/build-cost/performance gates are qualified.

Decision record: `docs/design/public-customization-decision.md`.

M4 exits with concrete production families and qualified internal composition,
not a universal framework.

## Later candidates

- UniqueBuffer / owned contiguous storage where consumer evidence supports it;
- ScratchBuffer / Arena families;
- synchronized bounded queues;
- concurrent work-stealing deque and other explicitly concurrent families.

Later milestones are admitted only when their contracts, consumers, safety and
performance gates are explicit.
