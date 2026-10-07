# ScratchBuffer public API

Status: production candidate  
Tracking: issue #59  
Research: issue #27, PR #58

## Purpose

`ScratchBuffer!T` owns one reusable contiguous typed backing allocation.

It is intended for thread-confined temporary work storage whose capacity should
survive repeated reset/reuse cycles while existing algorithms continue to
consume borrowed slices.

It is not a general vector, arena, pool, or transferable resource abstraction.

## Public module

```d
import containers.scratch_buffer : ScratchBuffer;
```

The package root also re-exports the type:

```d
import containers : ScratchBuffer;
```

## Type

```d
ScratchBuffer!T
```

The first public family has runtime capacity.

`.init` is an inert empty state with zero capacity.

## Ownership and identity

ScratchBuffer uniquely owns its backing allocation.

- implicit copy construction is disabled;
- identity assignment is disabled;
- whole-owner move construction transfers backing ownership in O(1);
- moving the owner does not relocate live T objects;
- the moved-from source becomes the inert zero-capacity state.

The first family is thread-confined.

## Live prefix

Exactly `length` T objects are live and occupy the physical prefix
`[0 .. length)`.

Public observation:

```d
size_t capacity;
size_t length;
bool empty;
bool full;
ref T opIndex(size_t index);
T[] opSlice();
```

Const overloads are provided for indexed and slice access.

`buffer[]` borrows exactly the live contiguous prefix.

## Borrow invalidation

Borrowed refs/slices do not own storage.

They are invalidated by:

- successful append or other structural mutation;
- `reset()`;
- successful capacity growth;
- whole-owner move;
- owner destruction.

A failed `tryPushBack`, failed live `tryReserve`, or no-op reserve that
already has sufficient capacity leaves the existing structure unchanged.

DIP1000 negative compile gates prevent refs/slices from escaping a local owner.

## Append

```d
bool tryPushBack(U)(auto ref U value);
```

The operation:

- appends one value when spare established capacity exists;
- returns false when full;
- never reallocates;
- never overwrites an existing live element;
- preserves qualified D language move construction where applicable.

The caller controls whether/when capacity should be re-established.

## Reset

```d
void reset();
```

Reset:

- ends every currently live T lifetime;
- keeps the backing allocation and capacity;
- leaves length zero;
- performs no backing allocation/deallocation.

For trivial pointer-free T, reset specializes to O(1) logical length reset.

For destructor-bearing or GC-visible-indirection T, required lifetime end and
vacated-slot sanitation remain explicit.

## Empty-only capacity establishment

```d
bool tryReserve(size_t minCapacity);
```

Semantics:

- if `capacity >= minCapacity`, returns true without changing storage;
- if growth is required while `length != 0`, returns false without
  allocation, relocation, or mutation;
- if growth is required while empty, backing storage is replaced with exactly
  `minCapacity` slots and true is returned;
- no geometric growth policy is embedded;
- no automatic shrink occurs;
- no live T is copied or moved during reserve;
- successful growth invalidates previous borrows.

Allocation failure follows the existing runtime-storage fatal OOM contract.
The boolean result reports the semantic inability to grow while live, not OOM.

## Alignment and GC visibility

Backing allocation preserves T alignment, including qualified over-aligned
types.

For T containing GC-visible indirections:

- external storage is registered with the GC while owned;
- newly acquired storage is cleared before registration/use;
- vacated live slots are cleared during reset;
- storage replacement removes the old range and registers the new range.

These behaviors are internal implementation guarantees, not policy knobs.

## Internal implementation

The public family uses package-internal mechanisms:

- `RuntimeStorageOwner!T` for unique aligned ownership and GC registration;
- `RuntimeStorageAccessOps!T` for consumer-local pointer/slice codegen;
- element lifetime mixins for placement move and destruction.

Those mechanisms are not public customization APIs.

## Performance contract

Performance is part of the family contract.

Qualified research evidence shows:

- exact DMD 2.111 retired-instruction parity with a direct manual
  preallocated-array + logical-length baseline for retained-capacity reuse;
- equal optimized LDC 1.41 wrapper code;
- representative DCanvas-like, geometry-like and OSM/raster-like profiles in
  the same performance class as direct manual storage.

The production promotion retains those gates.

## Explicit non-goals

The first API does not provide:

- live-content reallocation/growth;
- automatic geometric growth;
- automatic shrink;
- heterogeneous Arena allocation;
- BufferPool acquire/release semantics;
- cross-thread synchronization;
- object pooling;
- custom release callbacks;
- public allocator/storage policy parameters;
- public UniqueBuffer ownership abstraction;
- high-water telemetry.

Those semantics require independent evidence and, where admitted, separate
families.
