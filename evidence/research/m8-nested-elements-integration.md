# M8 containers-d nested element integration

Tracking: issue #10.

Qualified integration state:

```text
1052f053fa4cbefeb13ecdf27d3236834df20b22
```

GitHub Actions qualification:

```text
M8 Containers Integration
run 37896888365
```

All six jobs completed successfully as research harness jobs:

- DMD 2.111.0
- DMD 2.112.1
- DMD 2.113.0
- LDC 1.41.0
- LDC 1.42.0
- LDC 1.43.0

Individual internal construction failures are recorded research data.

## Public contract result

The tested context-bearing local struct reports, on all six compilers:

```text
isNested=true
hasIndirections=true
```

and all four public raw-storage families reject it at compile time:

```text
StaticRingBuffer: false
StaticVector:     false
RingBuffer:       false
ScratchBuffer:    false
```

The rejection therefore occurs before any unsafe runtime construction path is
reachable.

## Trait boundary

The same matrix distinguishes four local shapes:

```text
plain local:        isNested=false / hasIndirections=false
move-bearing local: isNested=true  / hasIndirections=true
capturing local:    isNested=true  / hasIndirections=true
static local:       isNested=false / hasIndirections=false
```

The current Phobos `std.traits.hasIndirections` contract explicitly includes
a nested context pointer as an indirection. For the contract relevant here,
`isNested` identifies the semantic boundary and `hasIndirections` follows
from the hidden context representation.

## Raw-storage result

`InlineRawStorage!(T, Capacity)` itself can represent the tested nested type
on all six compilers:

- storage instantiates;
- storage advertises indirections to the GC;
- slot addresses satisfy `T.alignof`;
- no T lifetime is begun merely by creating storage.

This separates storage representation from element construction.

## Construction-path result

### Direct placement at the lexical call site

Direct placement construction into an `InlineRawStorage` slot succeeds in
this probe on all six compilers:

```d
auto placed = new (*storage.slotPointer(0)) Nested(41);
```

The probe is defined in the same lexical function scope that owns the nested
type's context, so the compiler has the required frame context available.

This does not imply that a generic container implementation can reproduce the
operation.

### core.lifetime.emplace

The generic `emplace` path compiles but terminates with SIGSEGV 139 on all six
tested compilers for the same nested type.

That path is relevant because ordinary non-move insertion in the container
families delegates construction to `emplace`.

### PlacementMoveOps

The package-internal `PlacementMoveOps` bridge does not compile for the
nested type on any tested compiler. The diagnostic is:

```text
cannot access frame pointer of ...Nested
```

The bridge is generated from reusable container machinery rather than from the
lexical scope that owns the nested context. It therefore cannot supply the
hidden frame pointer required by the nested element.

### Static control

A function-local `static struct` has no hidden context
(`isNested=false`) and the equivalent internal storage/construction control
passes on all six compilers.

## Interpretation

M8 distinguishes two separate facts:

1. there is a DMD-specific placement-new regression for some primitive nested
   placement expressions, tracked separately by the minimal reproducer; and
2. independently of that regression, generic raw-storage container machinery
   cannot portably synthesize the hidden lexical context required by an
   `isNested` struct.

The second fact is sufficient for the containers-d public contract.

A generic container owns storage and element lifetime, but it does not own the
caller's lexical frame. Reconstructing or byte-copying hidden context would
make compiler representation details part of the container contract and is not
admissible.

## M8 decision

Outcome: **C — unsupported by contract** for struct element types where
`__traits(isNested, T)` is true.

This applies to the raw-storage families:

- `StaticRingBuffer`;
- `StaticVector`;
- `RingBuffer`;
- `ScratchBuffer`.

Function-local or nested-looking types for which `isNested` is false are not
rejected by this rule merely because of declaration location; they remain
subject to the ordinary element contract.

The public restriction should be expressed directly in terms of
`isNested!T`. Combining it with `hasIndirections!T` is redundant and makes
the semantic reason less explicit.

No runtime workaround, context-pointer copying, or public policy parameter is
justified.

## Production follow-up

Production work should:

1. make the four public family guards express the `isNested` restriction
   directly;
2. keep diagnostics consistent;
3. add ordinary negative/compile-contract regression coverage for the four
   families;
4. document the unsupported boundary without presenting it as a temporary DMD
   workaround;
5. leave `InlineRawStorage` package-internal and avoid implying that raw
   representability equals constructibility.
