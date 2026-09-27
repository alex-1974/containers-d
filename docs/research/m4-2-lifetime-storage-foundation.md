# M4.2 — Internal lifetime and raw-storage foundation

Status: active research  
Tracking: issue #29  
Parent: issue #23

## Purpose

M4.2 tests whether multiple future container families can share the deepest
memory/lifetime machinery without weakening the already-qualified v0.1 ring
buffer contracts.

The experiment is intentionally internal:

- no public API additions;
- no public allocator/backend parameter;
- no production RingBuffer/StaticRingBuffer refactor yet;
- no assumption that factoring is automatically zero-cost.

## Existing evidence

The two v0.1 ring-buffer implementations already duplicate several language
capability probes and lifetime decisions:

- copy construction availability from an lvalue T;
- whether T has a language move constructor;
- whether that move construction is callable from @safe code;
- whether T has an elaborate destructor;
- whether T contains GC-visible indirections.

Runtime storage already has a separate backend seam:

```d
RuntimeStorageOwner!(
    T,
    Backend = AlignedStorageBackend
)
```

That seam currently remains package-internal and is therefore a useful
precedent rather than a public compatibility commitment.

## First research modules

### containers.internal.element_lifetime

The first increment centralizes *classification only*.

It does not yet centralize placement construction/destruction, because those
operations cross the most sensitive @trusted/lifetime boundary and should only
move after exact semantic and generated-code comparison.

Current probes:

- `elementCopyConstructible!T`;
- `safeLanguageMoveConstructible!T`;
- `hasLanguageMoveConstructor!T`;
- `elementNeedsDestruction!T`;
- `elementHasIndirections!T`.

### containers.internal.storage_contract

The first raw-slot concept requires only:

- `capacity`;
- mutable/const `slotPointer(index)`;
- mutable/const `slotSlice(start, count)`;
- those borrow operations callable from `@safe @nogc nothrow` code.

It deliberately does **not** require allocation/release operations. This keeps
inline and runtime-owned storage in the same slot-access concept without
pretending they have the same ownership mechanism.

Semantic obligations such as correct alignment, non-overlap and storage
lifetime cannot be proven by structural introspection; a custom storage
implementation remains responsible for those invariants.

## Why classification precedes operation factoring

The existing ring implementations have similar-looking code that is not always
semantically interchangeable.

Examples:

- whole-buffer move of StaticRingBuffer relocates/move-constructs elements;
- whole-buffer move of RingBuffer transfers backing ownership in O(1) and does
  not move T objects;
- insertion of T with a language move constructor uses placement construction
  at the final slot address;
- classic relocation types may use moveEmplace/opPostMove semantics.

Therefore the first safe shared layer is type classification and the minimal
slot-borrow shape.

Actual construction/destruction helpers will be admitted one operation at a
time and compared against the existing behavior.

## Proposed extraction sequence

1. Compile-time element classification.
2. Raw-slot structural concept.
3. Positive/negative attribute probes on DMD 2.111 and LDC 1.41.
4. Add an internal construction-at-unused-slot helper for the exact insertion
   semantics already used by both ring types. **Implemented in research:** the
   helper preserves @safe versus @system according to T's language move
   constructor, and a self-referential probe verifies construction at the final
   slot address.
5. Add explicit end-live-slot helper only if destructor/GC clearing ownership
   can remain storage-agnostic.
6. Build a research-only StaticVector on the shared layer.
7. Compare against geo-d/geo3-d ExpansionBuffer.
8. Only then prototype factoring an existing ring hot path.

## Safety boundary

The intended split is:

```text
consumer/backend responsibility
    alignment
    valid raw storage
    storage lifetime
    non-overlap
        |
        v
containers-d audited boundary
    begin T lifetime
    copy/move construction
    end T lifetime
    GC visibility/slot clearing coordination
        |
        v
family algorithm
    logical state
    index mapping
    append/pop/etc.
```

Consumer customization must not replace the element-lifetime rules.

## Performance qualification plan

Any production refactor must compare current and candidate code on both baseline
compilers:

- DMD 2.111;
- LDC 1.41.

Required dimensions:

- existing unit/adversarial tests;
- DIP1000 build/tests;
- @safe/@nogc/nothrow probes;
- generated code/assembly for representative hot operations;
- retired instructions where practical;
- whole-operation benchmark throughput/latency;
- executable/text size;
- compile time and template-instantiation counts.

No production code is switched merely because the shared abstraction is
cleaner.

## Immediate acceptance for this first increment

- both internal modules compile on the baseline CI matrix;
- RuntimeStorageOwner satisfies the raw-slot concept;
- a minimal inline raw-slot test implementation satisfies the same concept;
- a deliberately incomplete implementation is rejected at compile time;
- no package-root export changes;
- no public v0.1 type changes.


## Placement-move factoring experiment

M4.2 tested three ways to share the language move-construction bridge that was
previously duplicated inside StaticRingBuffer and RingBuffer.

The probe uses a move-only `@safe` element type and executes 1,048,576 direct
placement moves. The baseline is the previous local placement-new shape.

### Imported helper forms — rejected for DMD 2.111

Both of these forms were functionally correct:

- an imported static helper in a templated `ElementLifetimeOps!T` aggregate;
- an imported free function template instantiated for T.

LDC 1.41 compiled both to the same measured instruction count as the direct
baseline.

DMD 2.111 did not inline the imported helper across the module boundary:

| Compiler | Direct Ir | Imported helper Ir | Delta |
|---|---:|---:|---:|
| DMD 2.111 | 40,894,475 | 51,380,246 | +25.641046% |
| LDC 1.41 | 13,107,232 | 13,107,232 | 0.000000% |

Adding `pragma(inline, true)` to the imported static helper did not change the
DMD result.

These forms are therefore rejected for the placement-move hot path.

### Typed template mixin — admitted for continued research

`PlacementMoveOps!T` is a typed template mixin that:

- injects only the placement-move helper;
- injects no state;
- refers to no consumer fields;
- captures the centrally derived `HasMove` and `SafeMove` values as template
  parameters, so the consumer needs no extra imports;
- keeps the helper `@trusted` only when T's own language move construction is
  independently callable from `@safe` code;
- keeps the helper `@system` otherwise.

Measured result:

| Compiler | Direct Ir | Mixed helper Ir | Delta |
|---|---:|---:|---:|
| DMD 2.111 | 40,894,475 | 40,894,475 | 0.000000% |
| LDC 1.41 | 13,107,232 | 13,107,232 | 0.000000% |

The direct and mixed variants also produce identical checksums.

This is the first concrete M4.2 evidence that a narrowly scoped D template
mixin can share safety-sensitive container-family implementation code without
adding runtime overhead on either baseline compiler.

### Production-shape integration in the research branch

Both `StaticRingBuffer` and `RingBuffer` now mix in
`PlacementMoveOps!T`; their duplicated local placement-move implementations
have been removed.

No package-root API, object layout, capacity rule, ownership rule or FIFO
semantic changed.

After this integration:

- Fast CI passes on DMD 2.111 and LDC 1.41, including DIP1000 and consumer
  smoke tests;
- the targeted placement-move probe passes on both compilers with exact
  instruction-count equality against the direct baseline;
- runtime RingBuffer operation and wraparound probes remain green on both
  compilers.

The existing runtime operation/wraparound probes primarily exercise trivial
element types, so they are regression guards for the unaffected ordinary paths;
the dedicated placement-move probe is the performance evidence for this
specific factoring step.

## M4.2 design lesson

Do not assume that a compile-time abstraction is zero-cost merely because no
runtime policy object exists.

For DMD 2.111 in particular, *where generated code is instantiated* can matter.
The accepted rule from this experiment is:

- ordinary imported helpers are preferred when they benchmark equivalently;
- typed template mixins are justified for small hot-path operations when
  measured compiler behavior shows that local generation is required;
- string mixins remain unnecessary;
- mixins must inject no hidden state and should not depend implicitly on host
  field names;
- each such use needs a direct baseline probe before admission.


## Lifetime end versus vacated-slot sanitation

The next factoring step exposed a second important boundary.

Ending a live T lifetime and sanitizing the now-unused backing bytes are related
in container control flow but are not the same responsibility.

### Language lifetime

For a live struct T with an elaborate destructor, containers-d uses:

```d
destroy!false(*slot);
```

This runs the language destructor without resetting the object to `.init`.
After the call the slot no longer contains a valid T object.

For T without an elaborate destructor, no destructor operation is required.

M4.2 now models this through the package-internal typed mixin:

```d
EndElementLifetimeOps!T
```

The helper receives a T pointer and stops at the D language lifetime boundary.

### Storage sanitation

A vacated raw slot may still contain byte patterns that represent GC-visible
pointers.

Whether and how those bytes must be cleared depends on the backing storage and
its GC visibility, not on T's destructor semantics.

RuntimeStorageOwner already owns this operation:

```d
storage.clearVacatedSlot(index);
```

For indirection-bearing T it zeroes the corresponding T-sized byte region; for
pointer-free T the operation compiles to a no-op.

The storage research contract now makes this distinction explicit:

```text
isRawSlotStorage!(S, T)
    capacity
    slotPointer
    slotSlice

isReusableRawSlotStorage!(S, T)
    all raw-slot borrowing operations
    +
    clearVacatedSlot
```

The second concept is appropriate for storage that is repeatedly used for
construct/destroy/reconstruct cycles.

### Consequence

Do not create a generic helper that implicitly reaches into a host container's
`_storage` field.

The intended composition is instead:

```text
family/container control flow
        |
        +-- EndElementLifetimeOps!T
        |       ends T lifetime
        |
        +-- storage.clearVacatedSlot(index)
                removes stale storage roots/bytes as required
```

This preserves independent evolution of:

- D language object-lifetime rules;
- inline/raw storage representation;
- runtime owned storage;
- future external/pool storage.

The next gate is performance qualification of `EndElementLifetimeOps!T`
against the current direct `destroy!false` form before either ring container
is switched to it.
