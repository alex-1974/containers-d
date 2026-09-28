# Element lifetime placement-move factoring

Status: qualified research evidence  
Tracking: issue #29  
Baseline compilers: DMD 2.111.0, LDC 1.41.0

## Question

Can the raw-slot language move-construction bridge be shared across container
families without changing semantics or adding hot-path cost?

The historical implementation duplicated this operation inside
`StaticRingBuffer` and `RingBuffer`:

```d
return new (*target) T(__rvalue(source));
```

The target must already denote one unused, suitably aligned T slot. For a T
whose language move constructor is independently callable from `@safe` code,
only the placement-new lifetime transition is trusted. Otherwise the bridge must
remain `@system`.

## Probe

Benchmark:

`benchmarks/element_lifetime_move_probe.d`

Workflow:

`.github/workflows/perf-element-lifetime-move.yml`

Each measured variant performs 1,048,576 placement moves of the same move-only
`@safe` value type. Setup and output remain outside Callgrind collection.

Decision metric: retired instructions (Callgrind Ir).

The semantic gate requires equal checksums.

## Experiment A — imported helper aggregate

A shared static helper in an imported templated aggregate was functionally
correct.

Results:

| Compiler | Direct Ir | Shared Ir | Delta |
|---|---:|---:|---:|
| DMD 2.111.0 | 40,894,475 | 51,380,246 | +25.641046% |
| LDC 1.41.0 | 13,107,232 | 13,107,232 | 0.000000% |

`pragma(inline, true)` did not change the DMD result.

Decision: reject for this hot path.

## Experiment B — imported free function template

Moving the operation to a free function template did not remove the DMD
cross-module cost. DMD retained the same +25.641046% result.

Decision: reject for this hot path.

## Experiment C — typed template mixin

The accepted research form is:

```d
mixin PlacementMoveOps!T;
```

The mixin:

- injects no fields/state;
- depends on no host field names;
- captures the centrally classified `HasMove` and `SafeMove` values as
  template parameters;
- generates an `@trusted` placement bridge only when T's own move construction
  is independently `@safe`;
- otherwise generates an `@system` bridge.

Results:

| Compiler | Direct Ir | Mixed Ir | Delta |
|---|---:|---:|---:|
| DMD 2.111.0 | 40,894,475 | 40,894,475 | 0.000000% |
| LDC 1.41.0 | 13,107,232 | 13,107,232 | 0.000000% |

Checksums are identical.

The production-shaped research integration commit
`75478e3cadebe2ad3c434d130ad089d4a4c72bbe` uses the mixin in both
`StaticRingBuffer` and `RingBuffer`.

At that state:

- Fast CI passed on DMD 2.111 and LDC 1.41;
- the dedicated placement-move probe passed on both compilers with exact Ir
  equality;
- runtime RingBuffer operation and wraparound probes remained green.

## Interpretation

This is not evidence that template mixins are generally faster than ordinary D
templates.

It is narrower:

- the operation is small and hot;
- DMD 2.111 did not inline the tested imported forms across this module
  boundary;
- LDC 1.41 did;
- locally generated typed mixin code gave both compilers the direct baseline.

Therefore the architectural rule is evidence-driven:

1. prefer ordinary functions/templates when they qualify with no regression;
2. use a typed template mixin only when local generation is required by measured
   compiler behaviour;
3. inject no hidden state and avoid implicit host-field coupling;
4. keep string mixins out of this mechanism;
5. preserve a direct baseline benchmark for every hot-path factoring decision.

## Scope limit

The existing runtime RingBuffer operation/wraparound probes mostly exercise
trivial element types. They remain important regression guards, but they do not
by themselves measure the language move-constructor path.

This dedicated probe is the performance evidence for `PlacementMoveOps!T`.
