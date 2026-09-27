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

M3 is complete. The next milestone is deliberately not admitted here: choose
between release preparation and the next container family using the normal
issue/milestone planning process.

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

## Later candidates

- FIFO queues;
- LIFO/FILO stacks;
- deque-like structures where justified;
- SPSC ring buffers;
- other bounded container primitives.

Later milestones are admitted only when their contracts and consumer need are
clear.
