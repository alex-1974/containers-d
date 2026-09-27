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
