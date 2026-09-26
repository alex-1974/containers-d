# Ring-buffer wraparound arithmetic — performance evidence

Status: probe methodology committed; measured results are recorded after the
corresponding GitHub Actions run completes.

## Question

For the fixed-capacity ring buffer physical-index normalization, compare:

1. branch/subtract;
2. modulo by compile-time capacity;
3. power-of-two mask where the capacity permits it.

The decision must be compiler-specific where generated code differs.

## Method

See `benchmarks/ring_buffer_wrap_probe.d`.

The probe measures retired instruction count with Callgrind, with collection
toggled only around the selected benchmark function. Shared-CI wall-clock time
is not used as decision evidence.

Baseline compilers:

- DMD 2.111.0
- LDC 1.41.0

Capacities:

- 1000 (non-power-of-two): branch/subtract vs modulo;
- 1024 (power-of-two): branch/subtract vs modulo vs mask.

Operations per measured run: 1,048,576.

## Results

Pending the first `Ring Buffer Performance Probe` workflow run.

## Decision

Pending measured evidence.
