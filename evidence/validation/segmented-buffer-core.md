# Segmented buffer validation

The v0.3.0 segmented buffer core is validated by the module unittests under
both DMD and LDC. The tests cover:

- empty and multi-segment append;
- exact segment boundaries;
- bounded overflow;
- partial front consumption;
- reset and capacity reuse;
- generic non-trivial element destruction;
- byte-specific package-root exposure.

The implementation uses one independently owned runtime allocation per
segment. Segment metadata stores pointers to separately allocated segment
owners so growing the metadata table cannot bitwise-relocate a move-only
storage owner or invalidate earlier segment addresses.
