# Runtime RingBuffer sequencing-core validation

Issue: #15  
Scope: provisional runtime-capacity FIFO sequencing core, not yet package-root
exported.

## Implemented core

`RingBuffer!T` currently provides, package-internally:

- inert `.init` / capacity-zero state;
- runtime `capacity`, `length`, `empty`, and `full`;
- logical `front`, `back`, and indexed access;
- non-overwriting `tryPushBack`;
- FIFO `popFront`;
- `clear` retaining backing storage;
- disabled automatic copy and identity assignment;
- O(1) whole-buffer ownership move;
- inert moved-from state;
- vacated-slot clearing through `RuntimeStorageOwner!T`;
- overflow-safe runtime physical-index calculation.

The type remains package-visible in `containers.runtime_ring_buffer` and is not
re-exported from `containers`.

## Constructor attributes

A generic owning container constructor cannot unconditionally promise
`@safe @nogc nothrow` for every T because D construction failure cleanup is
coupled to the container destructor, and the destructor destroys live T
elements.

Therefore constructor/move-constructor attributes are inferred from the actual
instantiation.

For a trivial element type, the executable compile probe confirms that
construction, push/pop, whole-buffer move, and clear are usable from:

```d
@safe @nogc nothrow
```

This is an operation/type-specific guarantee rather than a false universal
claim.

## Runtime indexing

The first runtime implementation uses an overflow-safe branch/subtract form:

```text
tailRoom = capacity - head

if offset < tailRoom:
    head + offset
else:
    offset - tailRoom
```

This remains correct even for capacities near the representable size_t limit.
M3.3 will decide whether additional runtime state or specialization is justified
by measured performance.

## Tests

Validated cases include:

- `.init` and explicit capacity zero;
- zero-capacity insertion rejection;
- capacity one;
- fill/full/non-overwrite;
- FIFO pop;
- physical wraparound and reuse;
- clear followed by reuse without storage-capacity loss;
- logical indexing/front/back across wrap;
- copy and identity assignment rejection;
- O(1) whole-buffer move;
- moved-from inert state;
- no element copy/move during whole-buffer ownership move;
- non-trivial element destruction balance;
- deterministic 20,000-step adversarial comparison against a linear reference
  model;
- trivial-element `@safe @nogc nothrow` compile probe.

## Compiler matrix

Final implementation head before this evidence commit:
`d47fa799ca95c310906585a1160581c5ae256726`

- DMD 2.111.0: Fast gate PASS
- LDC 1.41.0: Fast gate PASS
- DIP1000-on unit tests: PASS on both
- existing package-root external consumer: PASS on both
- existing negative segment-lifetime compile test: PASS
- documentation build: PASS
- release build: PASS

## Deferred public admission work

This core is intentionally not the final public M3 surface.

Still required before `RingBuffer!T` is exported:

- contiguous first/second segment access with revalidated pointer-owned lifetime
  annotations;
- end-to-end GC reachability evidence with live indirection-bearing T;
- public package-root consumer;
- public Ddoc/README contract;
- final admission review.

Runtime hot-path specialization remains M3.3 rather than a blocker for the
semantic core.
