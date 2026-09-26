# Ring-buffer semantic core

Status: design contract for the first implementation branch.

This document specializes the workspace engineering contract for the first
container family in containers-d. It defines the semantics that implementation
work must preserve. It intentionally does not prescribe a concurrency model.

## 1. Scope

The first implementation target is a bounded, single-threaded ring buffer with
compile-time capacity:

`StaticRingBuffer!(T, Capacity)`

A runtime-capacity `RingBuffer!T` is a later milestone and must preserve the
same observable sequence semantics where the storage model allows it.

SPSC, MPSC and MPMC queues are separate container families. Their atomicity and
memory-ordering contracts must not leak into this type.

The initial ring-buffer core is not a deque abstraction. The primary mutation
direction is append at the logical back and removal at the logical front.

## 2. Logical model

A ring buffer represents one ordered logical sequence of live `T` values.

For every valid state:

```text
0 <= length <= Capacity

empty <=> length == 0
full  <=> length == Capacity
```

For the static-capacity type:

```text
Capacity > 0
capacity == Capacity
```

The logical element at index zero is the front element. Logical indexing is
independent of physical wraparound.

The implementation may store the sequence in one or two physical contiguous
segments, but callers observe one ordered sequence.

## 3. State representation

The initial representation should prefer the smallest state that makes the
invariants obvious:

- physical index of the logical front;
- number of live elements;
- storage for exactly `Capacity` potential slots.

A separate tail index is not required by the semantic contract. If performance
evidence later shows that retaining one is beneficial, it may be added provided
the extra invariant is validated.

The physical insertion position for an append operation is derived from the
front index plus the current length with wraparound.

No slot is reserved merely to distinguish empty from full. `length`
distinguishes those states, so all `Capacity` slots are usable.

## 4. Element lifetime

Logical emptiness and object lifetime are not the same thing.

The intended generic contract is:

- exactly `length` slots contain live `T` objects;
- unused slots do not represent live `T` objects merely because storage exists;
- insertion constructs a `T` in an unused slot;
- removal destroys the removed live `T` exactly once;
- `clear` destroys every live element exactly once;
- destruction of the container destroys every remaining live element exactly
  once.

This is the preferred contract because the library must not require every
potential slot to hold a permanently default-initialized `T`.

Therefore a plain `T[Capacity]` representation is not accepted as the generic
implementation merely for convenience. Raw inline storage is expected for the
static-capacity type unless an equally correct representation is demonstrated.

Any raw-storage implementation must:

- preserve `T.alignof`;
- never form a reference to a slot before a `T` lifetime has begun there;
- never access a slot after that lifetime has ended;
- keep all `@trusted` code at the smallest auditable boundary;
- provide negative/adversarial tests for the lifetime assumptions.

## 5. Copy, move and destruction semantics

The container must not rely on accidental bitwise copying of raw storage for
non-trivial `T`.

Copy construction is element-wise and mirrors `T`'s copyability. When `T` is
not copyable, buffer copy construction is disabled.

Whole-buffer move construction currently has one explicit temporary
restriction: element types that define a D language move constructor are not
accepted for buffer move construction on the baseline implementation.

The reason is concrete rather than theoretical. DMD 2.111
`core.lifetime.moveEmplace` implements raw relocation with
blit/`opPostMove`/wipe semantics and does not dispatch the newer language move
constructor. Silently using that path for such a `T` could bypass invariants
encoded in `T.this(T)`.

For element types without a language move constructor, the implementation uses
`moveEmplace` into uninitialized inline storage, explicitly destroys the
wiped moved-from source object, and then removes that slot from the source
buffer's live-element accounting.

Support for element language move constructors remains a research/implementation
item and must be solved without weakening the baseline compiler contract.

Before `StaticRingBuffer` is admitted to the public facade, its behavior must
be correct for the supported non-trivial element categories and every temporary
restriction must be explicit.

Silently supporting only trivial element types is not acceptable.

Tests must include non-trivial copy/destruction cases, ownership-transfer cases,
and compile-time rejection of unsupported move-constructor element categories.

## 6. Overflow and underflow

Overflow behavior is explicit.

The baseline insertion API must provide a non-overwriting operation whose
failure is observable, for example:

```text
tryPushBack(value) -> bool
```

When the buffer is full, that operation:

- returns failure;
- does not allocate;
- does not overwrite an existing element;
- does not modify the logical sequence.

Overwrite-on-full behavior, if added, must use a separately named operation or
policy. It must never be an implicit side effect of the ordinary insertion
operation.

Operations requiring a non-empty buffer may use a documented precondition.
A fallible removal API may be added separately when its output/lifetime
semantics are defined precisely.

## 7. Initial public surface

The first implementation should aim for a deliberately small API:

```text
capacity
length
empty
full

front
back
opIndex

tryPushBack
popFront
clear
```

Names are provisional until implementation probes confirm that the signatures
work cleanly with D lifetime, move/copy and attribute inference.

Additional APIs such as emplacement, overwrite-on-full, mutable segment access,
iterators/ranges and bulk operations are admitted separately.

## 8. Borrowed access

References, slices, ranges or segment views into the buffer borrow the
container's storage.

Their invalidation rules must be documented before they are exposed publicly.

At minimum, structural mutation that begins or ends element lifetimes must be
assumed to invalidate borrowed views unless a stronger contract is proven.

DIP1000 may strengthen compile-time lifetime checking for consumers, but the
package must not force preview language switches through `dub.sdl`.

## 9. Wrapped segment access

A useful low-level ring-buffer operation is access to the live sequence as up
to two contiguous physical segments.

The eventual contract should be equivalent to:

```text
firstSegment.length + secondSegment.length == length

logical sequence ==
    firstSegment followed by secondSegment
```

When the logical sequence is physically contiguous, the second segment is
empty.

Segment access is not required for the first implementation commit, but the
storage design must not make it unnecessarily expensive.

## 10. Allocation contract

`StaticRingBuffer!(T, Capacity)` owns inline storage.

For container bookkeeping itself:

- construction performs no heap allocation;
- insertion/removal performs no heap allocation;
- wraparound performs no heap allocation;
- clear/destruction performs no heap allocation.

Operations performed by `T` itself may allocate. The container must not make a
stronger `@nogc` claim than the instantiated element operations permit.

Template attribute inference should be preferred where it accurately reflects
the behavior of `T`.

## 11. Wraparound arithmetic

The public contract does not require a power-of-two capacity.

The baseline implementation should use arithmetic that works for every positive
capacity.

Candidate hot-path forms include branch-based wraparound and compiler-optimized
constant modulo. Power-of-two masking is an optimization for qualifying
capacities, not a semantic requirement.

The final implementation choice is performance-evidence driven on the supported
DMD/LDC baselines.

## 12. Safety contract

The intended ordinary public API is `@safe`.

If raw storage requires `@trusted`, the trusted boundary must only perform the
operation the compiler cannot verify, such as converting an aligned slot address
into a pointer/reference to a live `T`.

Validation of indices, live-slot state and public preconditions remains outside
that trusted boundary.

## 13. Required first-wave tests

Before the type is exported from `source/containers.d`, tests must cover:

- initial empty state;
- capacity one;
- fill to exact capacity;
- insertion failure while full with unchanged contents;
- repeated wraparound;
- FIFO logical order across wraparound;
- front/back/index access across wraparound;
- transition empty -> non-empty -> full -> non-full -> empty;
- clear from contiguous and wrapped states;
- instrumented construction/destruction counts;
- non-trivial element lifetime;
- alignment of live `T` objects;
- no container bookkeeping allocation in steady-state operations;
- DMD and LDC baseline behavior;
- `@safe` use from consumer code where claimed;
- DIP1000-on and DIP1000-off compilation where lifetime annotations are used.

Adversarial operation sequences should compare the ring buffer with a simple
reference sequence model.

## 14. Performance evidence

Correctness comes first, but the representation is designed for predictable
hot paths.

Benchmark at least:

- append when not wrapping;
- append at wrap boundary;
- front removal when not wrapping;
- front removal at wrap boundary;
- indexed traversal;
- two-segment bulk traversal.

Compare alternative index-wrap implementations rather than assuming modulo,
branching or masking is universally best.

Record compiler version, optimization mode, element type and capacity with every
result.

## 15. Admission gate

`StaticRingBuffer` is not exported from the package facade until:

1. storage/lifetime behavior is executable-test backed;
2. non-trivial element behavior is resolved;
3. the normal API is usable from `@safe` code as claimed;
4. package CI is green on the Fast compiler pair;
5. performance probes show no avoidable hot-path regression;
6. documentation and tests describe the same overflow and invalidation rules.
