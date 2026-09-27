# M3.1 runtime-storage allocator research

## Workspace constraints

The workspace requires ownership/lifetime/allocation semantics to be explicit,
disallows surprising deep copies, scopes `@nogc` claims to real operation
contracts, and keeps unsafe operations in small auditable boundaries.

## D allocator findings

### std.experimental.allocator

The standard-library allocator package is still named and documented as
experimental. It is opt-in and supports both statically composed allocators and
type-erased allocator interfaces.

Its documentation recommends statically typed allocator composition for
performance-sensitive use and adapting to `IAllocator` only at a client
boundary when dynamic dispatch is needed.

Decision: useful internal mechanism/research reference; not exposed in the first
public `RingBuffer!T` signature.

### AlignedMallocator

The inspected D 2.111 source provides `AlignedMallocator` with:

- POSIX `posix_memalign`;
- Windows aligned allocation;
- `alignedAllocate(bytes, alignment)`;
- `@nogc nothrow` allocation;
- `@nogc nothrow` deallocation, marked `@system` because deallocation can
  invalidate aliases.

The implementation remains materially similar in inspected 2.113/current
sources.

Decision: suitable as the first private runtime-storage backend.

### GCAllocator

GC-backed allocation gives the collector native visibility into references, but
its allocation operation is not `@nogc`.

Decision: not selected as the default backend because M3 intends the owning
storage acquisition path itself to avoid GC-heap allocation.

### External C-heap memory and GC references

`GC.addRange` and `GC.removeRange` are `@nogc nothrow` and exist
specifically to make externally managed memory visible to the conservative GC.

`std.traits.hasIndirections!T` detects representations containing pointers,
arrays, class references, associative arrays, delegates, or context pointers.

Decision: register C-heap storage only for indirection-bearing element types and
keep unused registered slots zeroed to avoid stale conservative roots.

### Out-of-memory handling

`core.exception.onOutOfMemoryError` is `@nogc nothrow` and raises D's
`OutOfMemoryError`.

Decision: use normal D fatal allocation semantics for the initial constructor;
do not add a separate recoverable factory without a consumer.

## Alternatives not selected initially

### Public allocator template parameter

Pros:
- static dispatch;
- custom storage policy;
- can support regions/arenas.

Costs:
- allocator becomes part of the public type identity;
- stateful allocator ownership/lifetime becomes a user-facing contract;
- substantially larger genericity/test surface.

Decision: defer until a consumer requires it.

### Type-erased IAllocator

Pros:
- runtime allocator selection.

Costs:
- dynamic dispatch and allocator-object lifetime;
- larger owner state;
- experimental API exposure;
- no present consumer need.

Decision: do not use in initial public API.

### GC-owned backing allocation

Pros:
- automatic GC scanning.

Costs:
- construction uses GC allocation;
- less explicit ownership/deallocation behavior for this low-level owner;
- does not advance the desired independent `@nogc` storage path.

Decision: not the first backend.

### Hidden owned/borrowed mode in one type

Pros:
- fewer type names.

Costs:
- ownership and destructor behavior become runtime state;
- copy/move/lifetime semantics become ambiguous.

Decision: reject. A future borrowed external-storage abstraction is a distinct
type.
