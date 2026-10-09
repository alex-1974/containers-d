# M8 minimal nested placement-move reproducer

Tracking: issue #10.

This is the reduced follow-up to the qualified primitive matrix in
`evidence/research/m8-nested-elements-primitive-matrix.md`.

It intentionally contains:

- one function-local struct;
- one `int` payload;
- one user-defined language move constructor;
- one aligned raw slot;
- one placement `new (*ptr) T(__rvalue(source))`.

There is no containers-d import and no outer-value read.

## Modes

- `TraitsProbe` reports `isNested` plus compile traits.
- `OrdinaryMoveProbe` is the typed-storage control.
- `PlacementConstructProbe` instruments immediately before and after
  placement construction and does **not** destroy the placed value.
- `PlacementDestroyProbe` performs the same construction and destroys the
  value only after the post-construction marker was reached.

A crash in a probe process is recorded as evidence; it does not fail the
research workflow itself.

The six supported release compilers are compared so the first failing DMD
version and the corresponding LDC behavior remain visible.
