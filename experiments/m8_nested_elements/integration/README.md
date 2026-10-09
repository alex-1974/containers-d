# M8 containers-d integration probes

Tracking: issue #10.

This experiment starts only after the primitive DMD placement-new crash has
been reduced independently of containers-d.

It asks three repository-specific questions:

1. Does the public compile-time contract reliably reject the problematic
   nested/context-bearing element shape?
2. Can the package-internal inline raw-storage layer represent the same type
   without beginning a T lifetime?
3. What happens when the package-internal construction paths are exercised
   directly, bypassing the public family rejection?

No production source is modified by this experiment.

## Probe modes

- `PublicContractProbe`
  - records `isNested`, `hasIndirections`, and whether
    `StaticRingBuffer` / `StaticVector` instantiate;
- `InternalStorageProbe`
  - instantiates `InlineRawStorage`, checks alignment, and does not construct
    a T;
- `InternalEmplaceProbe`
  - constructs a nested value through the `emplace` path used by ordinary
    non-move insertion;
- `InternalPlacementMoveProbe`
  - constructs through the package-internal `PlacementMoveOps` bridge;
- `StaticControlProbe`
  - repeats the internal raw-storage + construction path with a function-local
    `static struct` whose `isNested` value is false.

Runtime failures in the internal construction probes are evidence and do not
fail the research workflow. The public contract and static control are expected
to remain stable across the supported compiler matrix.
