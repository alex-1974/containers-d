# Segmented buffer baseline probe

The probe is `benchmarks/segmented_buffer_append_probe.d`.

It compares three implementations over a 1 MiB byte workload with 4 KiB
segments:

- `candidate`: `SegmentedByteBuffer`;
- `manual`: preallocated independent `ubyte[]` segments;
- `flatten`: one preallocated contiguous `ubyte[]`.

All variants perform the same copy/reuse and traversal workload and return an
FNV-style checksum. With DMD `-O -release -inline -boundscheck=off`, the three
variants produced identical checksums for one and sixteen rounds:

```text
14837716285302907685
6574951863890879269
```

This establishes workload parity and functional equivalence for the probe. A
retired-instruction comparison is not included because Callgrind/Valgrind is
not installed in the current environment; CI should run the probe with the
repository's normal instruction-count tooling before making a performance
admission decision.
