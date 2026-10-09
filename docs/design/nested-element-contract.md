# Nested/context-bearing element contract

Status: M8 research decision  
Tracking: issue #10

## Decision

containers-d raw-storage container families do not support struct element types
for which `__traits(isNested, T)` is true.

The restriction applies to:

- `StaticRingBuffer`;
- `StaticVector`;
- `RingBuffer`;
- `ScratchBuffer`.

## Rationale

A nested D struct may carry an implicit context pointer to an enclosing lexical
or aggregate frame. The container can own raw storage, alignment, GC
visibility, and T lifetimes, but it does not own or reconstruct the caller's
lexical frame.

M8 showed that:

- package-internal raw storage can represent the bytes and GC scan shape;
- direct placement construction can work when emitted in the lexical scope
  that owns the context;
- generic `core.lifetime.emplace` is not a portable construction mechanism
  for the tested nested type;
- the shared placement-move bridge cannot access the required frame pointer;
- static/non-context-bearing local structs remain ordinary values.

Supporting context-bearing nested structs would therefore require the library
to depend on hidden compiler representation or to accept caller context as an
additional semantic input. Neither belongs in the current container-family
contracts.

## Enforcement

The contract boundary is `isNested!T` itself.

`std.traits.hasIndirections` also reports the hidden context pointer as an
indirection, but combining both traits is redundant. The diagnostic should name
the semantic reason: hidden/nested context is unsupported.

## Non-goals

This decision does not:

- forbid all function-local struct declarations;
- forbid `static struct` declarations inside functions;
- change ordinary module-scope element support;
- make `InlineRawStorage` a public customization mechanism;
- introduce context-pointer copying or compiler-specific reconstruction.

A local type with `isNested == false` remains eligible subject to the normal
element-type contract.

## Reconsideration gate

Reconsider support only if the D language/toolchain gains a portable generic
mechanism that lets reusable code construct a nested value with the correct
context without exposing compiler representation details or imposing runtime
cost on ordinary element types.
