# Changelog

All notable changes to `containers-d` are documented here.

The project follows Semantic Versioning for published releases.

## [0.2.0] - 2026-10-08

### Added

- `StaticVector!(T, Capacity)`, a fixed-capacity, variable-length contiguous
  inline vector with no backing allocation.
- Borrowed live-prefix access through D slice syntax `vector[]`.
- Precondition-based `pushBack` plus checked non-overwriting `tryPushBack`,
  `popBack`, `clear`, front/back and indexed access.
- Element-aware copy/move/destruction, GC stale-root cleanup and over-aligned
  storage qualification for non-trivial element types.
- Scalar specializations selected automatically at compile time to retain
  consumer-local runtime and build/code-size quality.
- `ScratchBuffer!T`, a reusable runtime-capacity contiguous typed scratch
  owner with retained capacity across reset/reuse cycles.
- Borrowed live-prefix access through `scratch[]`, explicit checked
  `tryPushBack`, and empty-only `tryReserve` that never relocates live
  elements.
- Package-internal runtime-storage access factoring that preserves DMD hot-path
  codegen while keeping allocation, alignment and GC ownership private.
- `WorkStealingDeque!(T, Capacity)`, a bounded fixed-capacity
  single-owner / multi-thief concurrent deque with owner `tryPush`/`pop`,
  thief `steal`/`stealBatch`, and caller-owned batch output.
- Explicit concurrent identity: copy, move, assignment, and pass-by-value forms
  are rejected; `.init` is a valid empty deque.
- `@safe @nogc nothrow` hot operations with a narrow internal ordering
  boundary, native x86_64/AArch64 correctness qualification, and pinned P08e
  code-generation/performance evidence.
- `BlockingQueue!T`, a bounded runtime-capacity synchronized FIFO for
  multiple producers and consumers, with non-blocking producer admission,
  blocking consumer wait, and explicit `pushed`/`full`/`closed` outcomes.
- Idempotent close-and-drain semantics for `BlockingQueue!T`: close rejects
  future pushes, preserves already queued work, and wakes blocked consumers.
- Native x86_64/AArch64 contention, synchronization-cost, wait/wake, and
  close/wake-all qualification for the BlockingQueue design.

## [0.1.1] - 2026-10-07

### Fixed

- `StaticRingBuffer!(T, Capacity)` now preserves `T.alignof` for over-aligned
  element types even when the buffer is embedded in another aggregate on
  compiler/target combinations that do not propagate over-alignment correctly.
- Pointer-bearing over-aligned inline storage now uses a conservative
  GC-visible scan shape when runtime base adjustment is required, and vacated
  slots are still cleared to avoid stale roots.

### Compatibility

- No public API names or operation semantics are changed.
- The minimum supported D frontend remains 2.111.0.

## [0.1.0] - 2026-09-27

Initial public development release of the bounded single-threaded ring-buffer
family.

### Added

- `StaticRingBuffer!(T, Capacity)` with compile-time capacity and inline raw
  storage.
- `RingBuffer!T` with runtime-selected capacity, unique aligned backing
  storage, inert capacity-zero state and O(1) ownership move.
- Non-overwriting `tryPushBack`, FIFO `popFront`, `clear`, front/back and
  logical indexed access.
- Zero-copy `firstSegment` / `secondSegment` access for contiguous processing
  of wrapped logical contents.
- Explicit live-element lifetime management for non-trivial element types.
- Language-move-constructor preservation for whole-buffer static moves and for
  exact-T rvalue insertion at the final storage address.
- GC range registration for runtime C-heap storage containing GC-visible
  indirections, with stale-slot clearing after removal.
- External consumer, DIP1000 borrow-lifetime, GC reachability and adversarial
  model validation.
- Reproducible Callgrind evidence for fixed- and runtime-capacity wraparound hot
  paths on the baseline DMD/LDC compilers.

### Changed

- Nested/local struct element types with hidden outer context are explicitly
  rejected in the v0.1 API until their lifetime/context contract is researched
  separately in issue #10.
- Runtime hot-path qualification retained the overflow-safe tail-room
  implementation; no compiler-specific or power-of-two runtime specialization
  is admitted by v0.1.0.

### Compatibility

- Minimum supported D frontend: 2.111.0.
- Baseline development compilers: DMD 2.111.0 and LDC 1.41.0.
- The v0.1 release gate qualifies the controlled DMD 2.111/2.112/2.113 and LDC
  1.41/1.42/1.43 matrix before publication.
