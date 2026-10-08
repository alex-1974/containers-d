# Work-stealing deque performance qualification

Status: active research evidence  
Tracking: issue #38  
Candidate: containers-d research WorkStealingDeque  
Reference: immutable concurrency-d R0.1 P08e commit `b35a92f3412da6ca8a666cca9c144b5a335e5988`

## Scope

The external concurrency-d repository is reference-only in this project.
No source, branch, issue, CI or scheduler design is modified there.

Performance work here asks only whether the containers-d adaptation adds cost
or exposes an implementation problem that containers-d should fix.

## Same-binary isolated hot-path parity

Candidate and reference are instantiated in the same executable, with equal
capacity and equivalent ulong element semantics.

Compile-time checks require:

- equal capacity;
- equal aggregate `sizeof`;
- equal aggregate `alignof`.

Callgrind retired-instruction results are exact-equality on both baseline
compilers:

| Compiler | Workload | P08e Ir | containers-d Ir | Delta |
|---|---|---:|---:|---:|
| DMD 2.111 | owner push/pop pair | 8,127,535 | 8,127,535 | 0 |
| DMD 2.111 | single steal | 7,078,959 | 7,078,959 | 0 |
| DMD 2.111 | batch steal | 3,392,570 | 3,392,570 | 0 |
| LDC 1.41 | owner push/pop pair | 3,809,447 | 3,809,447 | 0 |
| LDC 1.41 | single steal | 3,023,013 | 3,023,013 | 0 |
| LDC 1.41 | batch steal | 1,401,009 | 1,401,009 | 0 |

Checksums also match exactly.

Conclusion: the containers-d source/API adaptation has no measurable
instruction-count overhead in the isolated qualified hot paths.

## Contention wall-clock diagnostic

A paired wall-clock probe compares candidate/reference on the same GitHub
x86 runner. Producer and thieves are pinned using the same Linux affinity
mechanism used by the source R0.1 scheduler research.

The runner exposes four logical CPUs backed by only two physical cores.
Therefore this probe is **diagnostic only** and is not a production gate.

DMD pinned results are consistently close to parity (roughly within ±3% in
the qualified 1- and 3-thief cases).

LDC paired results are not stable enough to attribute to either implementation.
Across independent reruns, the same 3-thief single-steal comparison changed
from about 1.44x candidate/reference to 0.94x and 1.10x. The 3-thief batch
comparison simultaneously varied from about 0.66x to 0.99x and 0.77x.

These direction-changing results coexist with exact isolated instruction and
layout parity. They therefore do not justify a containers-d code change.

## Performance decision

Do not optimize the containers-d prototype in response to the unstable
contention wall-clock diagnostic.

Retain as production-relevant evidence:

1. exact same-binary semantic parity;
2. exact retired-instruction parity on DMD 2.111 and LDC 1.41;
3. equal aggregate size/alignment;
4. native x86_64 and AArch64 correctness;
5. the retained R0.1 scheduler-neighbourhood evidence as an immutable external
   reference, not as work continued by this project.

A stable wall-clock admission gate requires a qualification host with enough
physical cores for the requested topology and controlled affinity/noise.

Until such a host is used, direction-changing hosted-runner timings are
research diagnostics only.

## Native AArch64 physical-core qualification

The native qualification runner is ARM Neoverse-N2 with four physical cores
and one hardware thread per core.

The balanced paired benchmark uses:

- producer pinned to CPU 0;
- one thief on CPU 1 or three thieves on CPUs 1..3;
- equal candidate-first/reference-first sample counts;
- median of per-pair candidate/reference ratios.

Final exact-head results:

| Thieves | Batch | Paired ratio |
|---:|---:|---:|
| 1 | no | 1.02887 |
| 1 | yes | 0.988969 |
| 3 | no | 0.858148 |
| 3 | yes | 0.964866 |

All qualified workloads remain below the 1.10 material-regression threshold.

The same run exposes very large first/second execution-order effects in some
subcases. This validates the use of balanced per-pair ratios and explains why
earlier ratio-of-independent-medians measurements were not acceptable as a
promotion gate.

## Native AArch64 code-generation parity

On LDC 1.41 the normalized instruction streams are identical between the
containers-d candidate and the pinned P08e reference:

| Workload | Candidate instructions | Reference instructions |
|---|---:|---:|
| owner push/pop | 70 | 70 |
| single steal | 61 | 61 |
| batch steal wrapper | 4 | 4 |

Normalization removes only absolute function/branch addresses. Opcodes,
registers, memory ordering instructions and control-flow instruction forms must
remain identical.

## Final research performance conclusion

No containers-d-specific hot-path optimization is required before production
promotion.

The candidate has:

- exact semantic parity with pinned P08e;
- equal queue size/alignment;
- exact DMD/LDC retired-instruction parity on x86_64;
- exact LDC AArch64 normalized instruction-stream parity;
- no material regression on the four-physical-core AArch64 contention gate.

The external concurrency-d research remains immutable reference evidence. Any
future adoption by concurrency-d is a separate project decision.
