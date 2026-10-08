# Ring-family sequencing factoring

Status: qualified for production promotion  
Tracking: issue #45  
Research evidence: PR #46  
Baseline: `develop` at `f5c775d`

## Decision

Adopt only the common ring sequencing layer:

- `_head`;
- `_length`;
- logical-to-physical index mapping;
- head advance;
- front-consumption state normalization.

The mechanism is package-internal and generated in the consuming aggregate
through the typed `RingSequenceOps` mixin.

Do not factor:

- slot storage/access;
- StaticRingBuffer over-alignment representation;
- RuntimeStorageOwner;
- element construction/destruction;
- GC sanitation;
- borrowed segment provenance;
- copy/move ownership;
- allocation;
- synchronization;
- public policy/configuration.

## Direct sequencing evidence

Callgrind, 262,144 rounds.

| Compiler | Family | Direct Ir | Factored Ir | Delta |
|---|---|---:|---:|---:|
| DMD 2.111 | static capacity 4 | 18,415,648 | 18,415,648 | 0 |
| DMD 2.111 | static capacity 7 | 30,446,182 | 30,446,182 | 0 |
| DMD 2.111 | runtime capacity 7 | 32,543,338 | 32,543,338 | 0 |
| LDC 1.41 | static capacity 4 | 6,815,753 | 6,815,753 | 0 |
| LDC 1.41 | static capacity 7 | 15,204,377 | 15,204,377 | 0 |
| LDC 1.41 | runtime capacity 7 | 15,466,521 | 15,466,521 | 0 |

Semantic checksums are identical. Compile-time layout assertions also establish
that the mixin adds no state beyond the two `size_t` sequence words.

## Actual StaticRingBuffer evidence

The production-shaped StaticRingBuffer probe was built once from the candidate
and once from the exact `develop` baseline.

| Compiler | Path | Develop Ir | Factored Ir | Delta |
|---|---|---:|---:|---:|
| DMD 2.111 | normal alignment | 48,775,233 | 48,775,233 | 0 |
| DMD 2.111 | over-aligned | 73,941,084 | 73,941,084 | 0 |
| LDC 1.41 | normal alignment | 10,223,639 | 10,223,639 | 0 |
| LDC 1.41 | over-aligned | 14,942,239 | 14,942,239 | 0 |

Checksums are identical. This specifically demonstrates that factoring does not
change the v0.1.1 over-alignment fix or its ordinary hot path.

## Actual RingBuffer evidence

The production RingBuffer operation probe was likewise built from candidate and
baseline. Capacities 63 and 64 cover non-power-of-two and power-of-two runtime
capacities. Every measured workload is instruction-identical on both baseline
compilers.

DMD 2.111, capacity 63:

| Workload | Develop Ir | Factored Ir |
|---|---:|---:|
| index | 30,437,423 | 30,437,423 |
| push/pop | 142,651,698 | 142,651,698 |
| segments | 349,737,138 | 349,737,138 |
| mixed | 175,039,369 | 175,039,369 |

DMD 2.111, capacity 64:

| Workload | Develop Ir | Factored Ir |
|---|---:|---:|
| index | 30,437,423 | 30,437,423 |
| push/pop | 142,651,438 | 142,651,438 |
| segments | 349,745,198 | 349,745,198 |
| mixed | 175,091,759 | 175,091,759 |

LDC 1.41, capacity 63:

| Workload | Develop Ir | Factored Ir |
|---|---:|---:|
| index | 8,429,600 | 8,429,600 |
| push/pop | 34,627,601 | 34,627,601 |
| segments | 57,629,702 | 57,629,702 |
| mixed | 44,232,728 | 44,232,728 |

LDC 1.41, capacity 64:

| Workload | Develop Ir | Factored Ir |
|---|---:|---:|
| index | 8,429,600 | 8,429,600 |
| push/pop | 34,627,601 | 34,627,601 |
| segments | 57,630,742 | 57,630,742 |
| mixed | 44,232,728 | 44,232,728 |

All semantic checksums match the baseline.

## Regression gates

The exact research head also passed:

- Fast CI on DMD 2.111 and LDC 1.41;
- runtime RingBuffer operation probe;
- runtime wraparound probe;
- placement-move probe;
- lifetime-end probe;
- StaticRingBuffer over-alignment GC reachability;
- runtime GC reachability;
- DIP1000 and external-consumer gates;
- StaticVector regression gates.

## Architecture consequence

This is evidence for a reusable *sequencing mechanism*, not a universal ring
container. StaticRingBuffer and RingBuffer remain separate public families with
different storage, ownership, copy/move and allocation contracts.

Any future ring-family extension may reuse this package-internal mechanism only
when its semantics match exactly and its own generated-code evidence remains
neutral.
