# StaticVector versus geo/geo3 ExpansionBuffer mechanics

Status: qualified M4.3 microbenchmark evidence  
Tracking: issue #25  
Baseline compilers: DMD 2.111.0, LDC 1.41.0

## Question

Can a generic containers-d fixed-capacity vector reproduce the hot-path
mechanics of the duplicated geo-d / geo3-d ExpansionBuffer without measurable
runtime cost?

The hard baseline shape is:

```d
double[Capacity] data;
size_t length;
```

with:

- clear;
- append;
- indexed access;
- no allocation;
- `pure nothrow @safe @nogc`.

The relevant capacities appearing in the current expansion modules are 1, 2, 3
and 4.

## Candidate

The package-internal research type is:

```d
StaticVector!(double, Capacity)
```

used through a thin ExpansionBuffer-shaped adapter.

For Capacity 4 the prototype statically requires:

```text
sizeof == 4 * double.sizeof + size_t.sizeof == 40
```

and its basic binary64 operations are compiled from a
`pure nothrow @safe @nogc` probe.

## Benchmark

Source:

`benchmarks/static_vector_expansion_probe.d`

Workflow:

`.github/workflows/perf-static-vector-expansion.yml`

Each run performs 262,144 rounds. Per round it:

1. clears the buffer;
2. appends Capacity runtime-generated binary64 values;
3. indexes every active element;
4. folds values, round number and component position into a rolling checksum.

The baseline and candidate must produce identical nontrivial checksums.

The measurement is Callgrind retired instructions (Ir).

## Initial generic implementation

The first StaticVector prototype used an imported
`InlineRawStorage!(T, Capacity)` object and `core.lifetime.emplace`.

### LDC 1.41

LDC completely removed those abstraction layers. Baseline and candidate were
instruction-identical at all capacities.

### DMD 2.111

DMD retained cross-module helper calls.

At Capacity 4:

```text
baseline   17,563,686 Ir
candidate  78,381,101 Ir
```

Callgrind attributed the added cost primarily to:

- imported `slotPointer` calls;
- `core.internal.lifetime.emplaceRef`.

This version was rejected.

## First correction: local storage mixin + scalar store

The raw storage implementation was factored into a typed state+ops mixin so
StaticVector can generate its storage accessors in the consuming aggregate.
For scalar T, pushBack uses a direct local store rather than the measured
non-inlined `emplaceRef` path.

That removed the `emplaceRef` cost but DMD still emitted calls to
`slotPointer`.

At Capacity 4:

```text
baseline   17,563,686 Ir
candidate  56,361,005 Ir
```

This was still rejected.

## Accepted research form

The local storage accessors are now explicitly `pragma(inline, true)` and the
small cast-only `@trusted` lambda wrappers were removed from those accessors.

The semantic checksum was also hardened after an earlier symmetric XOR fold
cancelled to zero over the chosen round count.

### DMD 2.111

| Capacity | Baseline Ir | StaticVector Ir | Delta | Checksum |
|---:|---:|---:|---:|---:|
| 1 | 6,815,772 | 6,815,769 | -3 | 6,638,599,988,523,302,912 |
| 2 | 11,272,222 | 11,272,220 | -2 | 15,265,634,458,368,475,136 |
| 3 | 15,728,673 | 15,728,671 | -2 | 5,751,550,999,698,604,032 |
| 4 | 20,185,124 | 20,185,125 | +1 | 16,345,547,169,880,604,672 |

The full-run differences are between -3 and +1 retired instructions over
262,144 rounds.

### LDC 1.41

| Capacity | Baseline Ir | StaticVector Ir | Delta | Checksum |
|---:|---:|---:|---:|---:|
| 1 | 2,490,394 | 2,490,394 | 0 | 6,638,599,988,523,302,912 |
| 2 | 4,194,319 | 4,194,319 | 0 | 15,265,634,458,368,475,136 |
| 3 | 6,291,479 | 6,291,479 | 0 | 5,751,550,999,698,604,032 |
| 4 | 8,126,490 | 8,126,490 | 0 | 16,345,547,169,880,604,672 |

LDC is instruction-identical for all measured capacities.

## Interpretation

For this hard initial consumer, the generic family can be made effectively
zero-cost on both baseline compilers.

The important architecture lesson is not that every operation should become a
mixin.

The measured rule is:

1. keep semantic/storage logic shared;
2. use ordinary imported helpers when the compiler removes them;
3. where DMD 2.111 demonstrably retains a hot helper call, allow a small typed
   mixin to generate that helper in the consumer aggregate;
4. use direct scalar storage for scalar T when no language-level construction
   machinery is required;
5. keep these choices internal and automatic rather than exposing them as user
   policy switches.

No string mixins are required.

## Scope

This benchmark proves the fixed-vector mechanics used by ExpansionBuffer:
clear, append and indexed access.

It does not yet prove the cost inside a representative exact-expansion
algorithm. M4.3 therefore still requires an algorithm-level benchmark and real
geo-d / geo3-d research integration before public promotion.

## Current decision

The direct mechanics gate is **passed** for DMD 2.111 and LDC 1.41.

StaticVector remains package-internal research until the remaining M4.3 gates
are complete.
