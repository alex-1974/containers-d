# Static inline over-alignment qualification

Status: issue #31 research candidate qualified for the current Linux matrix; production StaticRingBuffer not yet changed  
Controlled compilers: DMD 2.111/2.112/2.113, LDC 1.41/1.42/1.43  
Controlled architectures: Linux x86_64 and Linux AArch64 where toolchains are available

## Question

Does the released StaticRingBuffer representation provide a type-level
alignment guarantee for an over-aligned element when the buffer is embedded in
another aggregate, and if not, can containers-d select a correct representation
at compile time without penalizing compiler/target combinations that already
handle native over-alignment correctly?

This is stronger than checking one standalone stack variable.

Probe:

`benchmarks/static_ring_alignment_probe.d`

Workflow:

`.github/workflows/probe-static-ring-alignment.yml`

Primary element:

```d
align(64) struct OverAligned64
{
    ulong value;
}
```

The matrix also covers an align(64) element containing a GC-visible class
reference, arrays of holders, arrays of storage objects and the ordinary
native-alignment case.

## Result matrix

| Compiler / target | Released ring native contract | Forced-native probe | Selected candidate | Over-aligned GC reachability |
| --- | --- | --- | --- | --- |
| DMD 2.111 / Linux x86_64 | FAIL | FAIL | dynamic aligned base | PASS |
| DMD 2.112 / Linux x86_64 | FAIL | FAIL | dynamic aligned base | PASS |
| DMD 2.113 / Linux x86_64 | FAIL | FAIL | dynamic aligned base | PASS |
| LDC 1.41 / Linux x86_64 | PASS | PASS | native direct base | PASS |
| LDC 1.42 / Linux x86_64 | PASS | PASS | native direct base | PASS |
| LDC 1.43 / Linux x86_64 | PASS | PASS | native direct base | PASS |
| LDC 1.41 / Linux AArch64 | PASS | PASS | native direct base | PASS |
| LDC 1.42 / Linux AArch64 | PASS | PASS | native direct base | PASS |
| LDC 1.43 / Linux AArch64 | PASS | PASS | native direct base | PASS |

The current evidence therefore identifies a compiler-family difference across
the controlled Linux matrix, not a transition between old and new compiler
versions.

### DMD x86_64

Across DMD 2.111, 2.112 and 2.113:

```text
qualified-inline-embedded-align 8
ring-type-contract-sufficient 0
forced-native-sufficient 0
storage-dynamic 1
storage-align 1
storage-size 255
reference-storage-dynamic 1
reference-storage-align 8
reference-storage-size 192
normal-storage-dynamic 0
normal-storage-size 24
```

For align(64), the released StaticRingBuffer reports only alignment 8 and can
be embedded at offset 8. A deliberately forced-native storage type can itself
report alignof 64 but still be embedded at an insufficient address. Merely
raising the nested storage type's alignof is therefore not a portable DMD fix.

The selected DMD candidate reserves `T.alignof - 1` bytes of slack and derives
the first slot from the actual runtime payload address. Every tested slot in
embedded holders, arrays of holders and arrays of storage objects is aligned to
64 bytes.

### LDC x86_64

Across LDC 1.41, 1.42 and 1.43:

```text
qualified-inline-embedded-align 64
ring-type-contract-sufficient 1
forced-native-sufficient 1
storage-dynamic 0
storage-align 64
storage-size 192
reference-storage-dynamic 0
reference-storage-align 64
reference-storage-size 128
normal-storage-dynamic 0
normal-storage-size 24
```

LDC propagates align(64) through the tested aggregate layers. The selected
candidate therefore keeps a native direct-base representation with no alignment
slack and no runtime base-adjustment arithmetic.

### LDC AArch64

LDC 1.41, 1.42 and 1.43 on the GitHub-hosted Linux AArch64 runner show the same
native result as LDC x86_64:

```text
qualified-inline-embedded-align 64
ring-type-contract-sufficient 1
forced-native-sufficient 1
storage-dynamic 0
storage-align 64
storage-size 192
reference-storage-dynamic 0
reference-storage-align 64
reference-storage-size 128
normal-storage-dynamic 0
normal-storage-size 24
```

This row is qualified independently rather than inferred from x86_64.

## Candidate representation family

The package-internal
`containers.internal.target_capabilities` module centralizes the qualified
compiler/target decision.

For the current matrix:

- DMD/Linux/x86_64 qualifies native embedding only up to native pointer
  alignment and therefore selects the dynamic aligned-base representation for
  align(64);
- LDC/Linux/x86_64 qualifies native embedding through align(64);
- LDC/Linux/AArch64 qualifies native embedding through align(64);
- unqualified compiler/OS/architecture combinations remain conservative and
  use the dynamic representation when T exceeds native pointer alignment.

No runtime dispatch is introduced. Selection occurs at compile time.

The ordinary alignment case remains direct-base and exact-size on every tested
compiler/architecture. The align(64) workaround therefore adds no alignment
arithmetic or padding to ordinary element types.

## GC-visible over-aligned elements

The dynamic representation cannot use an exact `T[Capacity]` pointer bitmap
because slot zero may move within the payload. It instead overlays the payload
with a conservative pointer-word scan shape and starts from zeroed memory.

The native representation retains the exact `T[Capacity]` GC scan shape.

The dedicated `tests/inline-storage-gc` integration test is now executed for
every row in the alignment matrix. It verifies that an align(64) element
containing a class reference:

1. remains reachable while resident in the inline storage;
2. has an aligned slot address;
3. becomes collectible after the element lifetime ends and the vacated slot is
   cleared.

All nine controlled rows pass.

## Layout cost

For the pointer-free align(64), capacity-three probe:

- native LDC representation: 192 bytes for 192 payload bytes;
- dynamic DMD representation: 255 bytes for 192 payload bytes.

The DMD candidate pays exactly the alignment slack required to find an aligned
base from arbitrary placement.

For the align(64), indirection-bearing, capacity-two probe:

- native LDC representation: 128 bytes;
- dynamic DMD representation: 192 bytes after slack plus pointer-word rounding
  for the conservative GC scan shape.

This layout cost is limited to the compiler/element combinations that require
the dynamic path.

## Release consequence

The released v0.1.0 StaticRingBuffer representation has a demonstrated
correctness gap for over-aligned element types on the controlled DMD x86_64
matrix. This is not only a performance issue.

A v0.1.x correction should therefore remain under consideration. Any patch
release must contain only the minimal representation correction, regression
coverage and contract documentation; unrelated M4 factoring must not enter the
hotfix.

Before changing the production representation, issue #31 still requires:

- generated-code and performance comparison of the candidate paths;
- proof that the ordinary-alignment hot path remains unchanged;
- DMD dynamic-path cost measurement versus semantically equivalent C++;
- LDC native-path comparison versus Clang where useful;
- supported-OS qualification or a conservative fallback for unqualified
  targets;
- a minimal patch-release design review.

## Principle

The public semantic contract is common; the machine representation need not be.

C++ is the performance reference, not the implementation template. The selected
D implementation may differ by compiler or architecture when compile-time
selection produces a faster or safer equivalent result.

## References

- issue #31: StaticRingBuffer over-alignment correction
- issue #29 / PR #30: M4.2 lifetime/raw-storage research
- PR #32: compiler/architecture alignment matrix
