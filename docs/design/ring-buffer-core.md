# Ring-buffer semantic core

Status: admitted v0.1 logical contract for `StaticRingBuffer` and `RingBuffer`; further API remains incremental.

This document specializes the workspace engineering contract for the first
container family in containers-d. It defines the semantics that implementation
work must preserve. It intentionally does not prescribe a concurrency model.

## 1. Scope

The v0.1 public family contains two bounded, single-threaded ring buffers:

- `StaticRingBuffer!(T, Capacity)`: compile-time capacity with inline storage;
- `RingBuffer!T`: runtime capacity with uniquely owned backing storage.

They preserve the same observable FIFO sequence semantics where their storage
and ownership models allow it.

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

Class and interface references are stored values, not owned referents.
Removing such a slot must not explicitly finalize the referenced GC object.
Explicit destruction is performed only for element representations with an
elaborate struct destructor. Vacated indirection-bearing storage is cleared so
stale pointer bytes do not remain conservative GC roots.


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

Whole-buffer move construction has two deliberately distinct element paths.

When `__traits(hasMoveConstructor, T)` is true, the destination element is
constructed at its final inline-storage address with D 2.111 placement new and
`__rvalue(source)`. This dispatches `T.this(T)` and therefore preserves
invariants implemented by a language move constructor, including
self-referential/internal-pointer repair.

Placement new is a language-level `@system` operation. The implementation
contains only that storage operation in a narrow trust boundary, and only when
ordinary move construction of `T` is independently accepted by `@safe`
code. An unsafe element move constructor must not be laundered into a safe
container operation.

For element types without a language move constructor, the implementation keeps
the classic `moveEmplace` path. This preserves the established
destructive-relocation/`opPostMove` contract used by types that repair
self-references after relocation.

After either path successfully begins the destination lifetime, the moved-from
source slot is explicitly destroyed exactly once and removed from the source
buffer's live-element accounting.

The implementation must not substitute `moveEmplace` for a language move
constructor: research on DMD 2.111/LDC 1.41 plus DMD 2.113/LDC 1.43 confirmed
that `moveEmplace` does not dispatch `T.this(T)`.

Tests include non-trivial copy/destruction cases, classic relocation ownership
transfer, language-move dispatch, and a self-referential element whose target
would be invalid after plain bit relocation.

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

These names form the admitted v0.1 surface. The public family also exposes
`firstSegment` and `secondSegment` for zero-copy access to wrapped contents.

Additional APIs such as separately named emplacement, overwrite-on-full,
iterators/ranges and bulk operations require separate admission.

## 8. Borrowed access

References, slices, ranges or segment views into the buffer borrow the
container's inline storage.

The first borrowed slice API is the contiguous segment pair described below.

Invalidation contract:

- a successful structural mutation that begins or ends an element lifetime
  invalidates all previously returned segment slices;
- a failed `tryPushBack` on a full buffer does not mutate the logical
  sequence and therefore does not invalidate existing segment slices;
- mutation of a live element through a returned mutable slice is non-structural
  and is reflected by `front`, `back`, indexing and later segment access;
- callers must not retain borrowed slices across destruction or move of the
  owning buffer.

This deliberately conservative rule leaves room for a stronger future
invalidation guarantee without making the initial contract unsafe.

The segment accessors use D's `scope return` member-function semantics because
their slices point into storage embedded directly in the struct. Under DIP1000,
returning such a slice from a shorter-lived local buffer is rejected at compile
time. This is covered by a dedicated negative compile test.

The package does not force preview language switches through `dub.sdl`; DIP1000
is exercised explicitly in CI.

## 9. Wrapped segment access

`StaticRingBuffer` exposes its live FIFO sequence as at most two contiguous
borrowed slices:

```text
firstSegment()
secondSegment()
```

Both have mutable and const overloads.

For every valid state:

```text
firstSegment.length + secondSegment.length == length

logical sequence ==
    firstSegment followed by secondSegment
```

Additional rules:

- empty buffer -> both segments are empty;
- physically contiguous logical contents -> the first segment contains the
  whole sequence and the second segment is empty;
- wrapped contents -> the first segment runs from the physical head to the end
  of inline storage and the second continues from physical slot zero;
- a full buffer whose head is zero is one contiguous segment;
- a full buffer whose head is non-zero is represented by two segments in FIFO
  order;
- segment access performs no allocation;
- the ordinary API is intended to remain `@safe @nogc nothrow`;
- segment slices do not imply thread safety or synchronization.

A dedicated wrapper/result type is intentionally avoided for this first API:
the two slice accessors expose exactly the two physical regions and introduce
no additional lifetime-bearing object.

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

A production optimization that selects between materially different source
shapes requires reproducible evidence on the supported compiler baselines.

The fixed-capacity physical-index specialization is backed by
`evidence/performance/ring-buffer-wraparound.md`.

The runtime-capacity implementation was separately qualified in M3.3 using
primitive and whole-operation workloads. The decision and rejected candidates
are retained in
`evidence/performance/runtime-ring-buffer-wraparound.md`.

Record compiler version, optimization mode, workload, element type and capacity
with every material performance result.

## 15. Admission gate

`StaticRingBuffer` is exported from the package facade only while the following admission conditions remain satisfied:

1. storage/lifetime behavior is executable-test backed;
2. non-trivial element behavior is resolved;
3. the normal API is usable from `@safe` code as claimed;
4. package CI is green on the Fast compiler pair;
5. performance probes show no avoidable hot-path regression;
6. documentation and tests describe the same overflow and invalidation rules.

For the v0.1 admitted surface these conditions are satisfied for the documented
element categories. D language move constructors are preserved for
`StaticRingBuffer` whole-buffer move construction and for exact-T rvalue
insertion in both public buffer families.

Nested/local struct element types with hidden outer context are explicitly
rejected in v0.1 pending the separate research tracked by issue #10.
