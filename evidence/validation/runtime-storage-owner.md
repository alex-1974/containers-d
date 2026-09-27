# RuntimeStorageOwner validation

Issue: #13  
Scope: private M3.2 storage-owner layer only.

## Validated contract

The private `RuntimeStorageOwner!T` implementation provides:

- inert `.init` and explicit capacity-zero state;
- checked `capacity * T.sizeof` sizing before allocation;
- aligned C-heap acquisition;
- alignment at least `max(T.alignof, AlignedMallocator.alignment)`;
- conditional `GC.addRange` / `GC.removeRange` for
  `hasIndirections!T`;
- zero-initialized registered storage;
- explicit vacated-slot zeroing helper for indirection-bearing `T`;
- disabled copy construction and identity assignment;
- O(1) ownership move;
- inert moved-from state;
- exactly-once release responsibility after move;
- operation-scoped `@safe @nogc nothrow` lifecycle use.

## Test backend

A private counting backend wraps the admitted aligned backend in unittests.

For positive capacity, the tested lifecycle proves:

```text
acquisitions == 1
releases     == 1
```

across an ownership move, with zero release from the moved-from owner.

No allocator/backend type is exposed through the package root.

## Safety boundaries

Two kinds of system operations are isolated:

1. aligned deallocation, whose safety depends on unique ownership;
2. `GC.addRange/removeRange`, which are `@system` on the D 2.111
   declarations even though they are `@nogc nothrow`.

The GC calls are each wrapped in a minimal trusted helper. The rest of GC-range
state management and owner lifecycle remains `@safe`.

The release path is marked `scope` so DIP1000 can prove that destroying a
moved-from scoped owner does not escape its storage slice.

## Compiler matrix

Final head: `5d079d9c6f5cec3ca72c5eabf795e8cbf8f6ddb2`

- DMD 2.111.0: Fast gate PASS
- LDC 1.41.0: Fast gate PASS
- DIP1000-on unit tests: PASS on both
- existing external package consumer: PASS on both
- existing documentation build: PASS
- existing release build: PASS

## Deferred integration proof

This private layer directly executes the required GC range registration calls
and verifies zeroing behavior. A full reachability test using live
indirection-bearing elements belongs to the public `RingBuffer!T` integration
gate, where element lifetime and storage registration can be exercised
together.

The owner itself deliberately does not know which slots contain live T objects.
