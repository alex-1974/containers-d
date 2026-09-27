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
