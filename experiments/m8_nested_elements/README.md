# M8 nested/local element primitive probes

Tracking: issue #10.

This experiment establishes the D-language and toolchain baseline for
function-local and context-bearing struct values before containers-d storage
machinery is involved.

The experiment is intentionally outside `source/`. It does not change the
public container contract.

## Probe categories

- `module_scope` — ordinary module-scope control type;
- `local_no_capture` — function-local struct that does not reference an
  enclosing local;
- `local_capture` — function-local struct that reads an enclosing local;
- `member_capture` — function-local struct declared inside a struct member
  function and reading the enclosing aggregate through that method context.

Each category is compiled independently in three modes:

1. `TraitsProbe`
   - reports `__traits(isNested, T)`, size and alignment;
2. `OrdinaryMoveProbe`
   - performs ordinary typed-storage language move construction;
3. `PlacementMoveProbe`
   - performs language move construction directly into aligned raw storage
     with placement new and then destroys the placed object.

Compile failure in a nested/context-bearing cell is research evidence, not a
workflow failure. The module-scope control cells must compile and run.

## Compiler matrix

Decision baselines:

- DMD 2.111.0
- LDC 1.41.0

Comparison compilers:

- DMD 2.113.0
- LDC 1.43.0

The workflow records compiler diagnostics verbatim so frontend differences are
not normalized away.

## Interpretation rules

- Do not infer support from a successful compile alone.
- Do not repair hidden context through raw byte copying.
- Distinguish default initialization from `.init` for nested structs.
- Do not change containers-d production code until the primitive behavior is
  understood and the M8 decision gate in issue #10 is reached.
