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
2. overflow-safe add/carry detection plus one subtraction;
3. direct runtime modulo;
4. direct mask for power-of-two capacities;
5. power-of-two detection performed in the measured operation;
6. construction-time classification represented by stored
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

Authoritative measurements:

```text
stage A initial head: 1fb691b9d9710ff9fc7ec4f893ac88e213a5838d
initial workflow run: 36334801915

add/carry head: 13431ca9613954510f9b0a72dce6ea2f0d1ae03d
add/carry workflow run: 36335171687

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

Except for the add/carry candidate, counts are identical across the three
capacities within each capacity class for a given compiler and strategy.
Add/carry varies slightly with the generated branch distribution, so its table
entry reports the measured range across all six capacities. The raw workflow
artifacts retain every capacity.

### DMD 2.111.0

| Strategy | Capacity class | Ir | Relative to tail-room |
|---|---|---:|---:|
| tail-room baseline | both | 12,607,524 | 1.000 |
| overflow-safe add/carry | all six measured capacities | 10,932,250–11,087,898 | 0.867–0.879 |
| runtime modulo | both | 9,461,790 | 0.751 |
| detect each operation | non-power-of-two | 18,898,978 | 1.499 |
| detect each operation | power-of-two | 16,801,826 | 1.333 |
| stored classification | non-power-of-two | 14,704,672 | 1.166 |
| stored classification | power-of-two | 12,607,520 | 1.000 |
| direct mask | power-of-two | 9,461,787 | 0.751 |

Observations:

- the overflow-safe add/carry form retires about **12.1–13.3% fewer
  instructions** than the current tail-room form across the tested capacities;
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
| overflow-safe add/carry | all six measured capacities | 14,295,066–14,532,634 | 1.132–1.151 |
| runtime modulo | both | 13,668,376 | 1.083 |
| detect each operation | non-power-of-two | 18,903,055 | 1.497 |
| detect each operation | power-of-two | 14,704,655 | 1.165 |
| stored classification | non-power-of-two | 16,801,806 | 1.331 |
| stored classification | power-of-two | 11,563,022 | 0.916 |
| direct mask | power-of-two | 8,429,586 | 0.668 |

Observations:

- the overflow-safe add/carry form costs about **13.2–15.1% more retired
  instructions** than the current tail-room form;
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
    modulo ~= direct mask < overflow-safe add/carry < tail-room
    stored classification does not improve the power-of-two path enough
    to offset its generic-path cost

LDC 1.41:
    direct mask < stored classification < tail-room < modulo
    for power-of-two capacity

    tail-room < modulo < overflow-safe add/carry < stored classification
    for non-power-of-two capacity
```

Absolute DMD and LDC instruction counts are not used to rank the compilers.
Only within-compiler candidate ordering is interpreted.

## Overflow-safe add/carry candidate

The measured add/carry candidate is:

```d
size_t index = head + logicalIndex;

if (index < head || index >= capacity)
    index -= capacity;

return index;
```

The `index < head` predicate detects unsigned carry. Given the RingBuffer
preconditions `head < capacity` and `logicalIndex < capacity`, the
mathematical sum is strictly below `2 * capacity`, so at most one ring
subtraction is required. If the machine addition wraps, unsigned subtraction
by `capacity` still yields the same representable value as the mathematical
`head + logicalIndex - capacity`.

This candidate therefore preserves the full runtime-capacity wrap semantics
without imposing a smaller public capacity domain.

Measurement makes it a **DMD-only research candidate at this stage**:

- DMD 2.111 improves by about 12.1–13.3% in retired instructions;
- LDC 1.41 regresses by about 13.2–15.1%.

It is not suitable as one shared implementation for both baseline compilers.

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
- overflow-safe add/carry for DMD, subject to whole-operation qualification;
- DMD runtime-modulo shape as code-generation evidence only, still subject to
  its overflow limitation;
- LDC direct power-of-two mask, subject to finding a selection mechanism whose
  total cost remains worthwhile in real RingBuffer operations.

No compiler-specific production path is admitted by stage A.

## Stage B — whole-operation qualification

Harness:

```text
benchmarks/runtime_ring_buffer_operation_probe.d
```

Workflow:

```text
.github/workflows/perf-runtime-ring-buffer-operations.yml
```

Authoritative corrected run:

```text
head: 2c9277f7d5fa79c81405941a89a718220c6a8c44
workflow run: 36335750788
runner: ubuntu-24.04
```

The operation probe measures:

- indexed access on a full wrapped ring;
- repeated `popFront` + `tryPushBack`;
- segment access while continuously rotating the ring;
- a mixed FIFO workload combining pop, push, indexed reads and occasional
  segment inspection.

Capacities are 63, 64, 1000 and 1024. Each measured workload executes
1,048,576 deterministic operations.

Three implementations are compared:

```text
actual
    the real public RingBuffer!size_t

tailroom
    a benchmark-local mirror of the relevant RingBuffer implementation,
    retaining the current physicalIndex algorithm

addcarry
    the same mirror with only physicalIndex changed to the overflow-safe
    add/carry candidate
```

Before measurement, all workloads and capacities require:

```text
actual checksum == tailroom checksum == addcarry checksum
```

on both DMD 2.111 and LDC 1.41.

### Calibration result

For every measured capacity and workload on both compilers:

```text
Ir(actual) == Ir(tailroom)
```

exactly.

This is important evidence that the benchmark-local mirror preserves the
relevant optimized hot-path shape of the production RingBuffer closely enough
for the add/carry comparison.

### DMD 2.111.0

Relative add/carry change versus the actual/tail-room baseline:

| Workload | Measured change |
|---|---:|
| indexed access | **+4.37% to +4.64%** |
| push/pop | **-0.86% to -0.87%** |
| rotating segment access | **-0.32%** |
| mixed FIFO | **+0.29% to +0.34%** |

The primitive stage-A add/carry advantage therefore does not survive uniformly
once the arithmetic is embedded in representative RingBuffer operations.

The only measured whole-operation improvements are below 1%, while indexed
access and the mixed workload regress.

### LDC 1.41.0

Relative add/carry change versus the actual/tail-room baseline:

| Workload | Measured change |
|---|---:|
| indexed access | **+42.27% to +43.78%** |
| push/pop | **+3.03%** |
| rotating segment access | **+1.82%** |
| mixed FIFO | **+6.39% to +6.58%** |

The add/carry candidate is therefore consistently worse than the current
implementation under LDC.

### Segment-workload correction

An earlier operation run used an invariant segment-only loop. LDC correctly
collapsed almost all repeated segment work, producing an unusable count of only
39 retired instructions for the nominal 1,048,576 iterations.

The corrected workload rotates the full ring before each segment query, so
`head` and the physical segment boundary change continuously. Only the
corrected run above is evidence for the segment path.

A separate earlier harness defect was also caught by the semantic gate:
mutating `tryPushBack` calls had initially been placed inside `assert(...)`.
Because `-release` removes assertion evaluation, that version did not execute
those pushes. The benchmark was corrected so mutations occur unconditionally
and only their returned status is asserted. No measurements from that failed
semantic run are used.

## M3.3 decision

### KEEP

- the current overflow-safe tail-room implementation in `RingBuffer!T`.

It is the only tested shape that remains strong across both baseline compilers
and representative runtime-capacity workloads without adding state, narrowing
semantics or creating a compiler-specific maintenance path.

### REJECT for the current RingBuffer implementation

- per-operation power-of-two detection;
- a shared stored power-of-two classification branch;
- overflow-safe add/carry as the general implementation;
- a DMD-specific add/carry implementation.

The DMD-specific candidate is rejected despite its better primitive count:
whole-operation evidence shows regressions in indexed access and mixed FIFO,
while its push/pop and segment improvements are below 1%.

### REJECT as a direct replacement under the current contract

- `(head + logicalIndex) % capacity`.

It remains useful code-generation evidence for DMD, but addition-before-modulo
does not preserve the full representable runtime-capacity contract when the
addition overflows.

### DEFER

- a dedicated power-of-two-only runtime container or another design in which
  mask selection is structurally free rather than paid inside every generic
  operation.

The direct mask itself is strong under LDC, but M3.3 found no selection scheme
for the existing generic `RingBuffer!T` that improves the power-of-two case
without materially penalizing the generic non-power-of-two path. No current
consumer requirement justifies a new specialized public type.

## M3.3 conclusion

M3.3 does **not** admit a runtime wraparound specialization.

The existing production implementation remains unchanged:

```text
runtime physicalIndex -> overflow-safe tail-room branch/subtract
```

This is a measured negative optimization decision, not an absence of
investigation. Stage-A primitive results and Stage-B whole-operation results
are retained so the same candidates need not be rediscovered without new
evidence.

## Next stage

M3.3 is complete once this evidence branch passes its final Fast CI and is
integrated.

No RingBuffer production-code change is required from the qualification.
Subsequent planning can therefore move to release preparation or the next
container family without carrying an unverified runtime wraparound
optimization.
