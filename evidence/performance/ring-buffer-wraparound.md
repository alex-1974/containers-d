# Ring-buffer wraparound arithmetic — performance evidence

Status: measured on PR #2.

## Question

For the fixed-capacity ring buffer physical-index normalization, compare:

1. branch/subtract;
2. modulo by compile-time capacity;
3. power-of-two mask where the capacity permits it.

The decision is evaluated separately for DMD and LDC.

## Method

See `benchmarks/ring_buffer_wrap_probe.d`.

The probe measures retired instruction count with Callgrind, with collection
disabled at process start and toggled only around the selected benchmark
function. Process startup, deterministic input generation and output formatting
are excluded from the measured region.

The workspace performance rule uses retired instruction count for CI evidence.
Wall-clock time from a shared GitHub runner is intentionally not used as a
decision metric.

### Environment

GitHub Actions:

- runner: `ubuntu-24.04`;
- workflow: `Ring Buffer Performance Probe`;
- original measurement run: `36275477188`;
- original measurement commit: `f1acb04cec9ba6749c6eb2cc270eaa536abb83cf`;
- hardened-harness confirmation run: `36276651706`;
- harness-hardening commit: `2023b49777d8560b281bd572a1af9691f55bfedc`.

The original harness returned its deterministic static input arrays by value.
After two exact reproductions, one later DMD CI run failed the semantic preflight.
No toolchain cause was inferred from that observation. The harness was hardened
to fill caller-owned static arrays by `ref` and to print every checksum before
comparison. The hardened harness reproduced all checksums and every recorded
`Ir` value exactly on both baseline compilers.

Compilers and flags:

- DMD 2.111.0: `-O -release -inline -boundscheck=off`;
- LDC 1.41.0: `-O3 -release -boundscheck=off`.

Callgrind:

- collection starts disabled;
- collection is toggled only for the selected `extern(C)` benchmark function;
- reported event: retired instruction references (`Ir`).

### Workload

Each variant processes 256 deterministic runtime-generated
`(head, offset)` pairs for 4096 rounds:

```text
256 * 4096 = 1,048,576 physical-index calculations
```

Capacities:

- 1000: branch/subtract vs modulo;
- 1024: branch/subtract vs modulo vs explicit mask.

Semantic equivalence is checked before measurement.

Checksums:

- capacity 1000: `514793472`;
- capacity 1024: `525770752`.

All compared variants for a given capacity produced the same checksum.

## Results

### DMD 2.111.0

| Variant | Capacity | Operations | Ir | Ir/op | Relative to branch |
|---|---:|---:|---:|---:|---:|
| branch/subtract | 1000 | 1,048,576 | 8,904,732 | 8.4922 | 1.000 |
| modulo | 1000 | 1,048,576 | 14,704,672 | 14.0235 | 1.651 |
| branch/subtract | 1024 | 1,048,576 | 8,908,828 | 8.4961 | 1.000 |
| modulo | 1024 | 1,048,576 | 7,364,634 | 7.0235 | 0.827 |
| mask | 1024 | 1,048,576 | 7,364,634 | 7.0235 | 0.827 |

Observations:

- At capacity 1000, modulo requires about **65.1% more retired
  instructions** than branch/subtract.
- At capacity 1024, modulo and explicit mask are instruction-identical in this
  probe.
- At capacity 1024, modulo/mask require about **17.3% fewer retired
  instructions** than branch/subtract.

### LDC 1.41.0

| Variant | Capacity | Operations | Ir | Ir/op | Relative to branch |
|---|---:|---:|---:|---:|---:|
| branch/subtract | 1000 | 1,048,576 | 9,768,983 | 9.3164 | 1.000 |
| modulo | 1000 | 1,048,576 | 12,103,707 | 11.5430 | 1.239 |
| branch/subtract | 1024 | 1,048,576 | 9,768,983 | 9.3164 | 1.000 |
| modulo | 1024 | 1,048,576 | 5,050,385 | 4.8164 | 0.517 |
| mask | 1024 | 1,048,576 | 5,050,385 | 4.8164 | 0.517 |

Observations:

- At capacity 1000, modulo requires about **23.9% more retired
  instructions** than branch/subtract.
- At capacity 1024, modulo and explicit mask are instruction-identical in this
  probe.
- At capacity 1024, modulo/mask require about **48.3% fewer retired
  instructions** than branch/subtract.

## Cross-compiler interpretation

The two compilers differ materially in absolute code generation, so absolute
DMD and LDC instruction counts are not compared as a compiler ranking.

The within-compiler ordering is consistent:

```text
non-power-of-two capacity:
    branch/subtract < modulo

power-of-two capacity:
    modulo == explicit mask < branch/subtract
```

Both DMD 2.111 and LDC 1.41 strength-reduce the compile-time
`% 1024` case to instruction counts identical to the explicit mask in this
probe.

The explicit mask is nevertheless preferable as the intentional power-of-two
specialization: it states the precondition directly and does not depend on
future compiler strength reduction to preserve the selected hot-path shape.

## Decision

For `StaticRingBuffer!(T, Capacity)` physical-index normalization:

```d
static if ((Capacity & (Capacity - 1)) == 0)
{
    index = (head + offset) & (Capacity - 1);
}
else
{
    index = head + offset;
    if (index >= Capacity)
        index -= Capacity;
}
```

Do not use general modulo for non-power-of-two capacities on the baseline
compilers.

This decision applies to the tested physical-index form where
`head < Capacity` and `offset < Capacity`, so one subtraction is sufficient.

## Limits

This probe establishes retired instruction count, not elapsed time or branch
misprediction cost. Shared GitHub CI is not a controlled timing machine.

A future controlled-machine benchmark may add cycle/time evidence, especially
for unpredictable branch distributions, but it must not replace these
reproducible instruction-count results.

The probe covers the workspace baseline compilers only:

- DMD 2.111.0;
- LDC 1.41.0.

Later compiler-specific optimization work should rerun the same harness before
changing the specialization.

## Reproducibility note

Instruction counts are deterministic for this Callgrind probe under the recorded
environment. Repeated successful runs produced the exact same counts, rather
than merely similar wall-clock samples.

Warm-up and median timing are not applicable to the selected decision metric:
the evidence is retired instruction count for a fixed deterministic workload,
not elapsed time. The semantic checksum preflight remains mandatory before every
instruction-count run.
