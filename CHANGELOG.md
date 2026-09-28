# Changelog

All notable changes to `containers-d` are documented here.

The project follows Semantic Versioning for published releases.

## [Unreleased]

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
