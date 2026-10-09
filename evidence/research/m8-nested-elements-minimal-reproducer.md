# M8 minimal nested placement-move reproducer

Tracking: issue #10.

Qualified reproducer state:

```text
e8c27de742bed5c623627b5b12453199108e9b42
```

GitHub Actions run:

```text
M8 Minimal Reproducer
run 37893141734
```

All six workflow jobs completed successfully as research harness jobs. Probe
process failures are recorded data rather than workflow failures.

## Reduction

The reproducer is independent of containers-d and lives in:

```text
experiments/m8_nested_elements/minimal/probe.d
```

The failing shape contains only:

- one function-local struct;
- one `int` payload;
- one user-defined language move constructor;
- one aligned raw byte slot;
- one placement expression:

```d
auto placed = new (*target) LocalValue(__rvalue(source));
```

The type does not explicitly read an enclosing local value. Nevertheless all
six compilers report:

```text
isNested=1
constructCompiles=1
initCompiles=1
sizeof=16
alignof=8
```

for this move-bearing local type on x86_64.

## Boundary probes

Four independent modes are compiled and executed:

1. trait/compile information;
2. ordinary typed-storage language move;
3. placement construction with markers immediately before and after the
   placement expression, with no explicit destruction;
4. placement construction followed by explicit destruction, but only after a
   post-construction marker.

## Result matrix

| Compiler | Ordinary move | Placement construct only | Placement + destroy |
| --- | --- | --- | --- |
| DMD 2.111.0 | PASS | PASS | PASS |
| DMD 2.112.1 | PASS | **SIGSEGV 139** | **SIGSEGV 139 before destroy** |
| DMD 2.113.0 | PASS | **SIGSEGV 139** | **SIGSEGV 139 before destroy** |
| LDC 1.41.0 | PASS | PASS | PASS |
| LDC 1.42.0 | PASS | PASS | PASS |
| LDC 1.43.0 | PASS | PASS | PASS |

For both failing DMD versions the construct-only process prints:

```text
before-placement-new
```

and then terminates with status 139. It never prints:

```text
after-placement-new
```

The destroy variant behaves identically and never reaches
`before-destroy`.

Therefore explicit destruction is excluded as the cause of the observed
failure.

## Baseline behavior

DMD 2.111.0:

```text
before-placement-new
after-placement-new
source=-1 target=21 sameAddress=1
```

and the destroy variant additionally reaches:

```text
before-destroy
after-destroy
```

LDC 1.41.0, 1.42.0, and 1.43.0 show the same successful boundary behavior.

## Interpretation

This reduction strengthens the M8 toolchain signal substantially:

1. containers-d is not involved;
2. explicit destruction is not involved;
3. an enclosing value capture is not required;
4. ordinary typed-storage move remains successful;
5. the failure is specific to placement construction of this nested
   move-bearing local type;
6. the regression appears between DMD 2.111.0 and DMD 2.112.1;
7. LDC 1.42.0 and 1.43.0 do not reproduce the DMD failure despite their
   corresponding DMD frontend bases.

The result is now small enough for source/specification review and likely
upstream-toolchain classification, but the issue should not be filed upstream
until the documented placement-new and nested-struct contracts are checked
against the reproducer.

## containers-d consequence

No production API change follows yet.

The released v0.2.0 contract does not qualify nested/context-bearing element
support. M8 should next determine whether this DMD behavior violates the
language/toolchain contract and, independently, whether containers-d can
support any nested subset with a portable zero-cost path.

Do not add byte-copy or context-pointer repair workarounds.
