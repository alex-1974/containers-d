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
