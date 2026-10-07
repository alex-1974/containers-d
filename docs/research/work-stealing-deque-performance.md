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

## Contention wall-clock qualification

The x86 GitHub runner exposes four logical CPUs backed by only two physical
cores. Its contention timings remain diagnostic only because owner plus three
thieves oversubscribe the physical topology and LDC results change direction
between reruns.

The native Linux AArch64 runner is materially better suited to this gate:

- ARM Neoverse-N2;
- four logical CPUs;
- four physical cores;
- one hardware thread per core;
- one NUMA node.

Producer is pinned to CPU 0 and thieves to CPUs 1..3.

The first ARM experiment still showed a strong order effect because each
candidate/reference sample pair always executed in one order. The benchmark
was therefore corrected to alternate candidate-first and reference-first
pairs and to report the median of pair-local ratios. This removes slow host
drift from the implementation comparison.

Qualified native AArch64 / LDC 1.41 paired ratios:

| Workload | containers-d / P08e median ratio |
|---|---:|
| 1 thief, single steal | 1.02497 |
| 1 thief, batch steal | 1.00929 |
| 3 thieves, single steal | 0.971833 |
| 3 thieves, batch steal | 1.07536 |

All four workloads pass the current material-regression gate of 1.10.

The same native ARM build also reports equal candidate/reference aggregate
size/alignment and equal normalized wrapper instruction counts:

- owner pair: 70 vs 70 instructions;
- single steal: 61 vs 61;
- batch wrapper: 4 vs 4.

## Performance decision

Do not modify the containers-d algorithm for performance at this stage.

Production-relevant evidence is now:

1. exact same-binary semantic parity;
2. exact retired-instruction parity on DMD 2.111 and LDC 1.41;
3. equal aggregate size/alignment;
4. native AArch64 normalized code-size parity;
5. native x86_64 and AArch64 correctness;
6. native four-physical-core AArch64 contention parity within the 10% material
   regression gate;
7. retained R0.1 scheduler-neighbourhood evidence as immutable external
   reference, not as work continued by this project.

The oversubscribed x86 hosted-runner wall-clock workflow remains diagnostic and
must not override the physical-core qualification evidence.

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
