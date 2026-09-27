# Public runtime RingBuffer admission

Issue: #17

## Public surface

`RingBuffer!T` is exported from the package-root `containers` module.

The admitted runtime-capacity surface provides:

- inert `.init` / capacity-zero state;
- runtime `capacity`, `length`, `empty`, `full`;
- `front`, `back`, logical indexing;
- non-overwriting `tryPushBack`;
- FIFO `popFront`;
- `clear` retaining backing capacity;
- O(1) whole-buffer ownership move without relocating live elements;
- disabled implicit copy and identity assignment;
- zero-copy `firstSegment` / `secondSegment`.

## Stored-reference lifetime correction

A container owns the stored value, not a class/interface referent.

The admission work corrected slot destruction in both ring-buffer families:

- `hasElaborateDestructor!T` -> explicitly destroy the struct value;
- class/interface references and other non-elaborate values -> do not call the
  referent finalizer;
- indirection-bearing vacated storage -> clear bytes so stale pointer
  representations do not remain conservative GC roots.

The static inline-storage representation also advertises possible element
indirections to the GC rather than hiding references in an opaque byte array.

## Runtime borrowed segments

Runtime segment views borrow the owning backing allocation.

Contract:

```text
firstSegment.length + secondSegment.length == length

logical sequence ==
    firstSegment followed by secondSegment
```

Successful structural mutation, owner move, or owner destruction invalidates
previously returned segment views.

A whole-source DIP1000 negative fixture verifies that a segment from a local
runtime buffer cannot escape its owner lifetime.

## End-to-end GC reachability

Dedicated integration project:

```text
tests/gc-reachability
```

The probe creates:

1. an unrooted control object;
2. a second object whose only intended root is a class reference stored in the
   runtime ring buffer's external C-heap allocation.

Repeated forced GC collection plus stack scrubbing establishes that the control
object is finalized while the buffered object remains live.

After `popFront`:

- the buffered referent is not finalized synchronously by the container;
- the vacated slot is zeroed;
- repeated collection then finalizes the formerly buffered object.

This jointly validates GC range registration, stored-reference removal
semantics, and stale-root removal.

## External consumer

The public consumer imports:

```d
import containers : RingBuffer, StaticRingBuffer;
```

and exercises runtime construction, push/pop, wrapped segments, O(1) owner
move, and clear from `@safe @nogc nothrow` code for `int`.

## Compiler matrix

Final admission head:

```text
23d58e3c075da8b1eeb517ede9a709da436e2a78
```

Workflow run:

```text
36326328054
```

Results:

- Fast / dmd-2.111.0: PASS
- Fast / ldc-1.41.0: PASS
- DIP1000 unit tests: PASS
- static + runtime borrowed-slice negative compile fixtures: PASS
- package-root external consumer: PASS
- package-root consumer with DIP1000: PASS
- runtime GC reachability integration: PASS
- Ddoc build: PASS
- release build: PASS

## Post-admission qualification

M3.3 subsequently completed runtime hot-path performance qualification in
issue #19 / PR #20.

Whole-operation evidence retained the existing overflow-safe tail-room
implementation and rejected the measured runtime specialization candidates for
the generic `RingBuffer!T` contract. See
`evidence/performance/runtime-ring-buffer-wraparound.md`.
