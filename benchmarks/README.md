# Ring-buffer wraparound performance probe

This probe compares three candidate implementations of the physical ring-buffer
index normalization:

```d
// branch/subtract
size_t index = head + offset;
if (index >= Capacity)
    index -= Capacity;

// modulo
size_t index = (head + offset) % Capacity;

// power-of-two mask
size_t index = (head + offset) & (Capacity - 1);
```

## Cases

- capacity 1000: branch/subtract vs modulo;
- capacity 1024: branch/subtract vs modulo vs power-of-two mask.

Each measured function processes 256 deterministic runtime-generated
`(head, offset)` pairs for 4096 rounds: 1,048,576 index calculations.

The runtime inputs prevent the compiler from replacing the entire workload with
a compile-time closed form while keeping identical input/load overhead for all
variants of a capacity.

## Measurement

The GitHub performance-probe workflow compiles the same source independently
with the workspace baseline compilers:

- DMD 2.111.0: `-O -release -inline -boundscheck=off`;
- LDC 1.41.0: `-O3 -release -boundscheck=off`.

Callgrind is run with collection disabled at process start and toggled only for
the selected `extern(C)` benchmark function. The reported `Ir` therefore
measures the benchmark function rather than process startup, pair generation or
printing.

Retired instruction count is the decision metric. Wall-clock measurements from
shared GitHub runners are intentionally not used as performance evidence.

The two variants for capacity 1000 must produce the same checksum. All three
variants for capacity 1024 must produce the same checksum.


# Element-lifetime placement-move probe

M4.2 also contains `element_lifetime_move_probe.d`.

It compares the historical direct placement-new helper with the shared
`PlacementMoveOps!T` typed template mixin for a move-only element type.

The probe exists because DMD 2.111 showed a measurable cross-module call cost
for equivalent imported helper/function-template experiments, while LDC 1.41
inlined them.

Each variant performs 1,048,576 placement moves under Callgrind.

Qualified M4.2 result:

| Compiler | Direct Ir | Mixed helper Ir | Delta |
|---|---:|---:|---:|
| DMD 2.111 | 40,894,475 | 40,894,475 | 0.000000% |
| LDC 1.41 | 13,107,232 | 13,107,232 | 0.000000% |

The semantic-equivalence gate also requires identical checksums.

This benchmark is specifically evidence for the placement-move factoring. The
existing ring wrap/operation probes remain separate tests for their respective
hot paths.
