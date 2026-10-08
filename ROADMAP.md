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

## M5 — Work-stealing deque family — complete

Tracking: issues #38 and #39. Research evidence: PR #54. Promotion: PR #55.

Qualified research result:

- bounded fixed power-of-two capacity;
- exactly one owner and zero or more thieves;
- P08e 63-bit marked-top protocol;
- owner `tryPush`/`pop`;
- thief `steal`/`stealBatch`;
- caller-owned batch output;
- trivial atomically shared-compatible transport values;
- non-copyable/non-movable concurrent identity;
- `@safe @nogc nothrow` callable hot operations with one narrow trusted
  sequential-consistency barrier;
- exact last-item, multi-thief, near-capacity, wrap and forced marked-top
  overlap correctness;
- native Linux x86_64 and native Linux AArch64 qualification;
- exact DMD/LDC retired-instruction parity against the pinned immutable P08e
  reference;
- exact normalized LDC AArch64 instruction-stream parity;
- balanced four-physical-core AArch64 contention parity with no material
  regression.

Production promotion exposes only the scheduler-independent container family.
PR #55 merged the qualified family to develop as
`030065bcc7030a1cae0d8ba7502f95a46e8546ce`.

concurrency-d remains an external read-only reference/consumer in this
repository; downstream adoption is a separate concurrency-d project decision.

No public size/empty/full snapshot is admitted in the first API.

## M6 — Reusable contiguous scratch storage — complete

Research tracking: issue #27. Research evidence: PR #58.  
Production tracking: issue #59.

Qualified research result:

- one uniquely owned contiguous typed backing allocation;
- inert zero-capacity `.init`;
- runtime capacity and exact live prefix;
- borrowed live slice;
- reset retains capacity and performs no backing reallocation;
- trivial pointer-free reset specializes to O(1);
- whole-owner move transfers storage without relocating live elements;
- empty-only `tryReserve` can increase capacity between work phases;
- reserve never copies/moves live T and embeds no geometric growth policy;
- alignment and GC-visible external-storage behavior reuse the qualified runtime
  ownership machinery;
- package-internal `RuntimeStorageAccessOps` restores exact DMD hot-path parity
  without exposing storage policy;
- retained-capacity DMD 2.111 reuse path is instruction-identical to a direct
  manual preallocated-array + logical-length baseline;
- LDC 1.41 optimized code is equal;
- DCanvas-like, geometry-like and OSM/raster-like profiles remain in the same
  performance class as manual equivalents.

Architecture decision:

- promote `ScratchBuffer!T` as a concrete public family;
- do not promote public UniqueBuffer now (#26 closed not planned);
- keep Arena, BufferPool and live-content growth separate/deferred;
- keep mathematical/caller-workspace algorithm APIs slice-based;
- no consumer repository migration is part of this promotion.

Production promotion completed through PR #60 and merged to develop as
`6b8df935417c1d095df15e24c886b4863f0416ae`.

## M7 — Bounded BlockingQueue over ring storage — complete

Research tracking: issue #28. Research evidence: PR #62.  
Production tracking: issue #63. Promotion: PR #64.

Qualified research result:

- separate synchronized family rather than a thread-safety policy on RingBuffer;
- fixed runtime capacity backed by the qualified `RingBuffer!T` family;
- one mutex + condition variable with MPMC semantics under that mutex;
- non-blocking producer admission with explicit `pushed`, `full`, and
  `closed` outcomes;
- blocking consumer with explicit value/closed result;
- idempotent close, close-and-drain, and wake-all semantics;
- predicate-loop protection against spurious condition-variable wakes;
- first element contract restricted to copyable `T`;
- no operation-time FIFO backing reallocation after construction;
- fair storage parity on DMD 2.111 and LDC 1.41;
- native LDC x86_64 and AArch64 contention qualification across capacities
  1, 16, and 256 and 1P1C/2P1C/1P2C/2P2C topologies;
- uncontended synchronization, wait/wake, and close/wake-all measurements in
  the same performance class as the equivalent manual Mutex/Condition queue.

Production promotion admits only the stable bounded blocking FIFO contract:

- `BlockingQueue!T`;
- `BlockingQueuePushResult`;
- `BlockingQueuePopResult!T` / `BlockingQueuePopStatus`;
- immutable `capacity`;
- `tryPush`, `waitPop`, and `close`.

The first public API deliberately omits immediately stale concurrent
`length`/`empty`/`full`/`closed` snapshots. Move-only synchronized
transfer and explicit destruction while active waiters exist remain deferred
research questions.

Consumer repositories remain read-only evidence sources; no DCanvas or
raster-d migration is part of this promotion.

Production promotion completed through PR #64 and merged to develop as
`2662a97b09b6aa619d150c727af13fc85852fea3`.

## M8 — Nested/local element qualification — research

Tracking: issue #10.

M8 qualifies the boundary between containers-d raw-storage/lifetime machinery
and D element types that may carry hidden lexical or aggregate context.

Research scope:

- distinguish module-scope, local-without-capture, local-with-capture and
  nested aggregate-context element types;
- record `__traits(isNested, T)` and observable context requirements;
- establish primitive D/toolchain reference behavior before involving
  containers-d;
- qualify placement construction, language move, copy where permitted,
  destruction, alignment and GC reachability;
- exercise the relevant paths through `StaticRingBuffer`, `StaticVector` and
  package-internal lifetime/raw-slot machinery;
- extend to runtime external storage only where primitive evidence shows that
  context-bearing values can be represented safely;
- compare DMD 2.111.0 and LDC 1.41.0 with supported newer compilers and canary
  compilers where needed to distinguish language semantics from toolchain
  defects;
- preserve zero-cost behavior and generated-code quality for ordinary
  non-nested element types.

M8 exits with one explicit evidence-backed contract:

1. supported nested/local categories;
2. a precisely defined partially supported subset with compile-time rejection
   of unsupported forms;
3. explicit unsupported-by-contract semantics; or
4. a reduced upstream toolchain defect before any public-contract change.

Raw byte copying of hidden context is not an admissible workaround.

No production API change is assumed before the research decision is complete.

## Later candidates

- Arena / BufferPool as separate families where consumer evidence justifies
  them;
- public UniqueBuffer only if future consumers require direct transferable
  contiguous ownership as an observable contract;
- other explicitly concurrent SPSC/MPSC/MPMC families.

Later milestones are admitted only when their contracts, consumers, safety and
performance gates are explicit.
