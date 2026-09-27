# Runtime ring-buffer wraparound — M3.3 stage A evidence

Issue: #19  
PR: #20  
Status: measured primitive wraparound stage; no production optimization admitted yet.

## Question

For the runtime-capacity `RingBuffer!T` physical-index normalization, compare
the current overflow-safe tail-room form against runtime alternatives without
assuming that the fixed-capacity M2 result transfers to runtime capacity.

Candidates:

1. current tail-room baseline;
2. direct runtime modulo;
3. direct mask for power-of-two capacities;
4. power-of-two detection performed in the measured operation;
5. construction-time classification represented by stored
   `powerOfTwoCapacity` state and a per-operation branch.

The benchmark is intentionally separate from production code.

## Baseline semantics

Current `RingBuffer!T.physicalIndex`:

```d
const tailRoom = capacity - head;

if (logicalIndex < tailRoom)
    return head + logicalIndex;

return logicalIndex - tailRoom;
```

This form is overflow-safe for the full runtime-capacity contract and remains
the semantic baseline.

## Method

Harness:

```text
benchmarks/runtime_ring_buffer_wrap_probe.d
```

Workflow:

```text
.github/workflows/perf-runtime-ring-buffer-wrap.yml
```

Authoritative first measurement:

```text
head: 1fb691b9d9710ff9fc7ec4f893ac88e213a5838d
workflow run: 36334801915
runner: ubuntu-24.04
```

Compilers and flags:

- DMD 2.111.0: `-O -release -inline -boundscheck=off`;
- LDC 1.41.0: `-O3 -release -boundscheck=off`.

Callgrind collection starts disabled and is toggled only around the selected
`extern(C)` benchmark function. The recorded event is retired instruction
references (`Ir`).

Each variant executes:

```text
256 deterministic runtime-generated operation records
x 4096 rounds
= 1,048,576 physical-index calculations
```

Capacities:

```text
non-power-of-two: 7, 63, 1000
power-of-two:     8, 64, 1024
```

Every operation record carries its capacity as runtime data. This prevents the
probe from accidentally measuring compile-time constant-capacity reduction.

Semantic checksum equivalence is verified before instruction-count
measurement.

## Results

The counts are identical across the three capacities within each capacity
class for a given compiler and strategy, so the tables show one representative
capacity plus the observed relative result. The raw workflow artifacts retain
all six capacities.

### DMD 2.111.0

| Strategy | Capacity class | Ir | Relative to tail-room |
|---|---|---:|---:|
| tail-room baseline | both | 12,607,524 | 1.000 |
| runtime modulo | both | 9,461,790 | 0.751 |
| detect each operation | non-power-of-two | 18,898,978 | 1.499 |
| detect each operation | power-of-two | 16,801,826 | 1.333 |
| stored classification | non-power-of-two | 14,704,672 | 1.166 |
| stored classification | power-of-two | 12,607,520 | 1.000 |
| direct mask | power-of-two | 9,461,787 | 0.751 |

Observations:

- direct runtime modulo retires about **25.0% fewer instructions** than the
  current tail-room form at every tested capacity;
- direct mask and modulo are effectively instruction-identical for tested
  power-of-two capacities;
- stored construction-time classification provides no meaningful power-of-two
  gain over the baseline and costs about **16.6%** on non-power-of-two
  capacities;
- recomputing power-of-two classification in the operation is substantially
  worse.

### LDC 1.41.0

| Strategy | Capacity class | Ir | Relative to tail-room |
|---|---|---:|---:|
| tail-room baseline | both | 12,623,896 | 1.000 |
| runtime modulo | both | 13,668,376 | 1.083 |
| detect each operation | non-power-of-two | 18,903,055 | 1.497 |
| detect each operation | power-of-two | 14,704,655 | 1.165 |
| stored classification | non-power-of-two | 16,801,806 | 1.331 |
| stored classification | power-of-two | 11,563,022 | 0.916 |
| direct mask | power-of-two | 8,429,586 | 0.668 |

Observations:

- the current tail-room form beats direct runtime modulo by about **8.3%**;
- an already-selected direct mask is about **33.2%** below the tail-room
  instruction count for power-of-two capacities;
- adding a stored-state branch retains only an **8.4%** power-of-two benefit
  while making non-power-of-two operations about **33.1%** more expensive;
- recomputing the power-of-two test in the operation is substantially worse.

## Cross-compiler result

The fixed-capacity M2 ordering does **not** transfer directly to runtime
capacity.

Measured ordering:

```text
DMD 2.111:
    modulo ~= direct mask < tail-room
    stored classification does not improve the power-of-two path enough
    to offset its generic-path cost

LDC 1.41:
    direct mask < stored classification < tail-room < modulo
    for power-of-two capacity

    tail-room < modulo < stored classification
    for non-power-of-two capacity
```

Absolute DMD and LDC instruction counts are not used to rank the compilers.
Only within-compiler candidate ordering is interpreted.

## Important semantic limit of the modulo probe

The direct modulo candidate computes:

```d
(head + logicalIndex) % capacity
```

For the small measured capacities this is semantically equivalent to the
baseline. It is **not yet an admissible replacement** for the public runtime
contract because the addition can overflow for sufficiently large abstract
`size_t` capacities before the modulo is applied.

No production decision may rely on the modulo result until either:

- an equally fast overflow-safe formulation is demonstrated; or
- a stronger capacity invariant is independently justified and documented.

The benchmark result therefore establishes a code-generation opportunity, not
permission to weaken the existing semantics.

## Stage A decision

### REJECT for production as currently shaped

- per-operation power-of-two detection;
- one stored-classification branch shared by all capacities.

Both add large costs on at least one baseline compiler/capacity class.

### KEEP as research candidates

- current tail-room baseline;
- DMD runtime-modulo shape, subject to preserving overflow semantics;
- LDC direct power-of-two mask, subject to finding a selection mechanism whose
  total cost remains worthwhile in real RingBuffer operations.

## Next stage

Do not change `RingBuffer!T` yet.

M3.3 stage B must qualify representative whole-operation paths:

- logical indexed access;
- push;
- pop;
- segment calculation;
- mixed FIFO workload.

The purpose is to determine whether the primitive arithmetic deltas remain
material once actual RingBuffer work is included.

Only after stage B should compiler-specific or power-of-two production
specialization be considered.
