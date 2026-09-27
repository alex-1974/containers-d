# Changelog

## Unreleased

### Added

- Initial repository structure.
- `StaticRingBuffer!(T, Capacity)` with inline storage, explicit live-element
  lifetimes, non-overwriting insertion, FIFO removal, indexed access, and
  compiler-tested wraparound specialization.
- Reproducible Callgrind evidence for power-of-two and non-power-of-two
  wraparound arithmetic.
- Borrowed contiguous segment access through `firstSegment` and
  `secondSegment`, including DIP1000 lifetime validation.
- Whole-buffer move construction for element types with D language move
  constructors, using placement new at the final inline-storage address.
- `RingBuffer!T` with runtime-selected capacity, unique backing-storage
  ownership, O(1) owner move, and zero-copy segment access.
- Correct reference-value removal semantics: stored class/interface references
  are cleared without explicitly finalizing the referenced object.
