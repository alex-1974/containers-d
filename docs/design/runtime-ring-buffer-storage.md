# Runtime-capacity ring buffer — storage and ownership contract

Status: M3.1 design decision for the first runtime-capacity owning ring buffer.

This document specializes the workspace ownership, lifetime, allocation and
safety rules for `RingBuffer!T`. It does not change the admitted
`StaticRingBuffer!(T, Capacity)` contract.

## 1. Goal

The first runtime-capacity type is:

```text
RingBuffer!T
```

It is an owning, bounded, single-threaded FIFO ring buffer whose capacity is
chosen at runtime.

It preserves the logical semantics of `StaticRingBuffer` where storage
ownership permits it:

- `0 <= length <= capacity`;
- FIFO order;
- explicit live-element lifetime;
- non-overwriting ordinary insertion;
- wrapped contents observable as at most two contiguous segments;
- no storage allocation during steady-state push/pop/clear.

The runtime-capacity type differs deliberately in ownership and copy/move
semantics.

## 2. Ownership is part of the type

`RingBuffer!T` owns exactly one runtime storage allocation when
`capacity > 0`.

`.init` is an inert owner state:

```text
data == null
capacity == 0
length == 0
head == 0
```

It is safe to inspect for emptiness, destroy, and move through lifecycle code.

Constructing with capacity zero performs no storage allocation and yields the
same observable empty/capacity-zero state.

A non-owning external-storage ring buffer is **not** represented by a hidden
mode inside `RingBuffer!T`. If admitted later, it receives a distinct
view/storage type and an explicit caller-owned lifetime contract.

## 3. Initial public allocator policy

The first public type does **not** expose an allocator template parameter,
`IAllocator`, or an allocator object.

Reasons:

1. no current consumer requires allocator selection;
2. allocator state/lifetime would become part of the public ownership contract;
3. type-erased allocator dispatch would add state and indirect calls to a
   low-level container;
4. `std.experimental.allocator` remains explicitly experimental;
5. the workspace prefers the smallest stable public surface until a concrete
   semantic need exists.

The allocation backend is private and replaceable.

The implementation may use Phobos allocator building blocks internally when
they satisfy the baseline toolchain and the public contract.

## 4. Initial backend

The selected first backend is the C heap through
`std.experimental.allocator.mallocator.AlignedMallocator`, isolated behind a
private runtime-storage owner.

Reasons:

- available on the minimum D 2.111 toolchain;
- cross-platform POSIX/Windows aligned allocation is already implemented;
- allocation is `@nogc nothrow`;
- alignment can be requested explicitly;
- the implementation has remained materially stable across the inspected
  2.111, 2.113 and current sources;
- using it internally does not expose the experimental allocator API to users.

The requested alignment is at least:

```text
max(T.alignof, platformAlignment)
```

because POSIX aligned allocation requires a valid dynamic alignment in addition
to the element's own alignment requirement.

The container does not use allocator reallocation for ordinary operation.

## 5. Raw storage and element lifetime

The allocation owns raw storage for exactly `capacity` potential `T` slots.

Allocation does not begin any `T` lifetime.

For every state:

- exactly `length` logical slots contain live `T`;
- insertion begins one lifetime;
- removal ends one lifetime exactly once;
- `clear` ends all live lifetimes but retains the storage allocation;
- destruction first ends all live lifetimes, then releases storage.

The raw-storage construction/destruction primitives follow the already admitted
`StaticRingBuffer` element semantics, including language move constructors,
classic `moveEmplace` relocation, and the existing safety boundaries.

## 6. GC visibility for element indirections

C-heap memory is not automatically scanned by D's garbage collector.

Therefore, when `hasIndirections!T` is true, the owning storage must register
its C-heap byte range with:

```text
GC.addRange
```

and remove that exact range before deallocation with:

```text
GC.removeRange
```

Both operations are `@nogc nothrow`.

Because registered ranges are conservatively scanned, stale bytes in unused
slots could otherwise retain unrelated GC allocations.

For `hasIndirections!T`:

- newly acquired storage is zeroed before it becomes an active registered
  backing store;
- after a live `T` lifetime ends, the vacated slot is zeroed before it is
  considered unused;
- only live slots may intentionally contain element pointer representations.

For `!hasIndirections!T`, this zeroing/GC-range work is not required by the
container contract.

This rule is about GC reachability, not ownership of the referenced objects.

## 7. Allocation failure and impossible size

For positive capacity, storage bytes are:

```text
capacity * T.sizeof
```

The multiplication is checked before allocation.

If the requested storage size is not representable in `size_t`, or aligned
allocation returns null, construction follows normal D allocation-failure
semantics and calls `core.exception.onOutOfMemoryError`.

This permits the owning constructor to remain `@nogc nothrow`; D
`OutOfMemoryError` is an `Error`, not a recoverable ordinary allocation
result.

The first API does not add a second fallible `tryCreate` path without a
consumer requiring recoverable allocation failure.

## 8. Allocation contract

Construction:

- capacity zero: no allocation;
- positive capacity: exactly one backing-storage acquisition attempt;
- no GC-heap allocation by the container;
- may perform one-time zeroing and GC-range registration for indirection-bearing
  `T`.

Steady-state:

- `tryPushBack`: no backing-storage allocation;
- `popFront`: no backing-storage allocation;
- `clear`: no backing-storage allocation and storage is retained;
- element operations themselves may have their own allocation behavior.

Destruction:

- destroys live elements;
- unregisters the GC range when registered;
- deallocates the owned block exactly once.

Where these claims are published, executable allocation-count/attribute probes
must back them.

## 9. Copy semantics

Automatic copy construction is disabled for the initial owning
`RingBuffer!T`.

A copy would require one of two surprising semantics:

- alias the same owned allocation, which would violate unique ownership; or
- perform a deep copy, which would allocate implicitly.

Neither is acceptable as an automatic struct copy contract.

If consumers require duplication later, it should be an explicitly named
operation such as `dup`/clone with documented allocation and element-copy
behavior.

This differs intentionally from `StaticRingBuffer`, whose entire capacity is
inline and whose element-wise copy requires no backing-storage allocation.

## 10. Move semantics

Whole-container move transfers storage ownership in O(1):

```text
destination receives:
    data
    capacity
    head
    length
    GC-range responsibility

source becomes:
    .init-equivalent inert owner
```

The move does not move or reconstruct individual elements because their backing
addresses do not change.

Therefore:

- no element move constructors run during container move;
- self-referential elements continue to point to the same heap addresses;
- no allocation occurs;
- the GC range, when present, remains registered at the same address;
- only the destination owner later removes the range and frees the block.

Identity assignment remains disabled initially until self-assignment,
destination cleanup, and failure guarantees are specified.

## 11. Storage owner boundary

The implementation should separate private storage ownership from ring
sequencing, conceptually:

```text
RingBuffer!T
    head
    length
    RuntimeStorageOwner!T
        data
        capacity
        acquire/release
        GC range registration
```

This private boundary exists to centralize:

- checked byte sizing;
- alignment;
- allocation/deallocation;
- GC registration;
- slot clearing when required;
- move-only ownership.

It is **not** a public allocator abstraction.

A small private generic backend hook may be used under tests so allocation and
deallocation counts can be proven without exposing allocator policy publicly.

## 12. Runtime indexing

M3.1 does not freeze a runtime wraparound micro-optimization.

The first implementation may use the universally correct branch/subtract form.

Power-of-two specialization at runtime is admitted only after measuring its
state cost and hot-path benefit on DMD/LDC. The compile-time
`StaticRingBuffer` result is evidence, not automatic proof for a
runtime-capacity representation.

## 13. Borrowed segment access

`firstSegment` and `secondSegment` remain zero-copy borrowed views into the
owning storage.

The existing invalidation rule remains:

- successful structural mutation invalidates previously returned segment
  slices;
- failed insertion on full does not;
- moving or destroying the owner invalidates views associated with that owner
  even though an implementation-level storage address may happen to remain
  unchanged.

Public lifetime annotations must be revalidated for the pointer-owned storage
representation rather than copied mechanically from inline-storage
`scope return` annotations.

## 14. Thread safety

`RingBuffer!T` is single-threaded/non-synchronized, matching
`StaticRingBuffer`.

Thread-safe SPSC/MPSC/MPMC structures remain separate types with separate
memory-order contracts.

## 15. First-wave executable gates

Before `RingBuffer!T` is exported from the package root, validate:

- `.init` inert owner semantics;
- capacity zero;
- checked byte-size overflow;
- over-aligned `T`;
- allocation failure path;
- exactly one storage acquisition for positive capacity;
- exactly one deallocation by the final owner;
- no storage allocation during push/pop/clear;
- copy construction rejected;
- O(1) owner move and inert moved-from state;
- no element move during owner move;
- non-trivial element destruction exactly once;
- `hasIndirections!T` GC reachability while elements are live;
- no stale-slot retention contract after pop/clear where practical to probe;
- wrapped/contiguous segment laws;
- adversarial reference-model equivalence;
- public `@safe` claims;
- public `@nogc/nothrow` claims;
- DIP1000 on/off where lifetime annotations apply;
- external package-root consumer;
- DMD 2.111 and LDC 1.41.

## 16. Deferred questions

Not part of the first runtime-capacity public type:

- caller-selected allocator;
- stateful allocator ownership;
- type-erased `IAllocator`;
- storage growth/reallocation;
- unbounded queues;
- borrowed external raw-storage construction;
- SPSC/MPMC concurrency;
- recoverable allocation-failure factory.

These may be admitted later only when a concrete consumer requirement justifies
the additional public contract.
