# StaticVector in a representative expansion-sum algorithm

Status: qualified M4.3 algorithm-level evidence  
Tracking: issue #25  
Baseline compilers: DMD 2.111.0, LDC 1.41.0

## Question

After qualifying isolated ExpansionBuffer mechanics, does StaticVector remain
competitive when those operations are embedded in a representative exact
expansion-sum control flow?

The probe mirrors the structure of geo-d / geo3-d
`fastExpansionSumZeroElim`:

- two Capacity-2 input expansions;
- one Capacity-4 result expansion;
- least-significant-first ordering;
- magnitude merge;
- FastTwoSum / TwoSum style accumulation;
- zero elimination;
- repeated clear/append/index/length/empty operations.

The arithmetic is local to the benchmark so containers-d keeps no dependency on
geo-d. Baseline and candidate execute identical arithmetic/control flow and
differ only in the buffer implementation.

## Benchmark

Source:

`benchmarks/static_vector_expansion_algorithm_probe.d`

Workflow:

`.github/workflows/perf-static-vector-expansion-algorithm.yml`

Measurement:

- 131,072 rounds;
- runtime-generated input values;
- identical non-zero rolling checksum required;
- Callgrind retired instructions.

Checksum for both implementations:

`10226656636972966693`

## Whole benchmark result

### DMD 2.111

```text
baseline   27,321,910 Ir
candidate  27,715,124 Ir
delta         393,214 Ir
delta          +1.439189 %
```

The delta is essentially three instructions per outer benchmark round.

### LDC 1.41

```text
baseline   26,725,412 Ir
candidate  25,676,831 Ir
delta      -1,048,581 Ir
delta          -3.923535 %
```

The StaticVector candidate is approximately eight instructions per round lower
in this synthetic caller under LDC.

## DMD profile interpretation

The important result is inside the expansion algorithm itself.

Callgrind attributes:

```text
fastExpansionSumZeroElim baseline   16,836,096 Ir
fastExpansionSumZeroElim candidate  16,836,096 Ir
```

The expansion-sum function is therefore instruction-identical on DMD 2.111.

The +393,214 whole-benchmark difference appears in the surrounding
`runAlgorithm` caller that constructs inputs and folds the output checksum,
not inside `fastExpansionSumZeroElim`.

This matters because the direct M4.3 mechanics probe independently showed
clear/append/index to be baseline-equivalent after the DMD-specific local
storage/inlining correction. The residual caller difference is therefore a
code-generation/register-layout effect of this synthetic combined loop rather
than a retained helper call in the expansion algorithm.

## Decision

The representative expansion-algorithm gate is passed for continued research:

- semantic checksums are identical;
- DMD's expansion-sum body is instruction-identical;
- LDC's whole benchmark is faster with the candidate;
- the DMD whole-caller difference is small, fully outside the measured
  expansion-sum body, and should now be tested in real geo consumer code rather
  than optimized against this synthetic harness.

M4.3 should not add further special cases merely to erase three caller
instructions per synthetic round.

The next evidence should come from a real geo-d / geo3-d research integration.

## Architecture lesson

The family approach has now shown three distinct compiler behaviours:

1. LDC often erases ordinary generic abstraction directly.
2. DMD 2.111 may require local typed generation for tiny storage/lifetime hot
   operations.
3. Once those measured boundaries are handled, the higher-level generic
   numerical algorithm can compile to the same instruction count as its
   hand-local storage baseline.

This supports keeping compiler adaptation internal to containers-d rather than
exposing compiler or inlining policy switches to consumers.
