# M6 ScratchBuffer Stage 1 performance evidence

Status: qualified research baseline  
Tracking: issue #27  
Research PR: #58

## Question

Can a reusable owning typed ScratchBuffer match a hand-written preallocated
array + logical-length baseline in the repeated-use hot path?

The measured loop performs:

1. logical reset;
2. append 64 runtime-derived int values;
3. iterate the borrowed live prefix;
4. repeat for 65,536 cycles.

Allocation/setup is outside the measured wrapper.

## Initial result

The first generic implementation was materially slower on DMD because imported
runtime-storage access helpers remained out of line.

After making trivial pointer-free reset O(1), the hardened DMD probe still
showed:

| Variant | DMD 2.111 Ir |
|---|---:|
| manual baseline | 13,434,905 |
| initial candidate | 14,483,487 |
| delta | +7.804908% |

Native disassembly identified one imported `RuntimeStorageOwner.slotSlice`
call per reuse cycle. Replacing it with slot-pointer construction exposed the
same problem one layer lower: `RuntimeStorageOwner.slotPointer` remained
out-of-line.

## Qualified D-native specialization

M6 introduced the package-internal typed `RuntimeStorageAccessOps!T` mixin,
the runtime-storage analogue of the already-qualified `InlineRawStorageOps`
strategy used by StaticVector.

Allocation, GC registration and unique ownership remain in
`RuntimeStorageOwner`. Only slot pointer/slice/sanitation arithmetic is
generated in the consuming aggregate.

After this change the DMD gap fell to +2.439005%.

The final remaining difference was an explicit empty-slice null special case.
ScratchBuffer only requires an empty slice of length zero; it does not promise
that the empty borrow has a null pointer. Building the live slice directly from
the owned backing pointer removed that branch.

Final Stage-1 result:

| Compiler | Manual Ir | ScratchBuffer Ir | Delta |
|---|---:|---:|---:|
| DMD 2.111 | 13,434,905 | 13,434,905 | 0 |
| LDC 1.41 | wrapper optimized equally | wrapper optimized equally | 0 |

DMD normalized wrapper code is also equal length at 50 instructions each.
LDC normalizes both wrappers to the same optimized form.

## Compact-owner hypothesis

A separate experiment changed `RuntimeStorageOwner` from:

```text
ubyte[] bytes + capacity
```

to:

```text
pointer + capacity
```

to remove one machine word.

This produced **no further ScratchBuffer codegen or Ir improvement** after the
local access mixin. It also required an additional explicit heap-pointer
provenance trust boundary.

Conclusion: compact owner representation is not justified by M6 evidence and
does not establish a need for a public `UniqueBuffer`.

The research branch restored the proven slice+capacity owner representation.

## Regression evidence

On the final Stage-1 representation:

- Fast CI passes on DMD 2.111 and LDC 1.41;
- Scratch external consumer and DIP1000 pass;
- Runtime RingBuffer operation probe passes on DMD/LDC;
- Runtime RingBuffer wrap/performance probe passes on DMD/LDC.

The local runtime-access mixin therefore improves ScratchBuffer DMD codegen
without weakening or slowing the existing runtime ring family.

## Stage-1 decision

ADMIT the narrow reusable ScratchBuffer semantic direction for continued
research.

Retain:

- one owned aligned runtime allocation;
- live contiguous prefix;
- explicit full result;
- reset retaining capacity;
- O(1) trivial pointer-free reset;
- element-aware destruction/GC sanitation;
- package-internal local runtime-access mixin.

Do not admit yet:

- public ScratchBuffer API;
- public UniqueBuffer;
- live growth/reallocation;
- Arena/BufferPool semantics;
- public high-water telemetry.

Stage 2 may test empty-only `reserve(minCapacity)` because it changes backing
storage only when no T objects are live.
