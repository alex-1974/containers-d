# StaticVector — promotion contract

Status: promotion candidate; not package-root API yet  
Tracking: issue #34  
Research proof: issue #25 / PR #33

## 1. Purpose

`StaticVector!(T, Capacity)` is a fixed-capacity, variable-length contiguous
sequence whose storage is part of the value itself.

It is intended for small bounded sequences where:
- the maximum element count is known at compile time;
- no backing allocation is desirable;
- contiguous access matters;
- the logical length varies at runtime.

The type is not a growable Vector and is not a ring buffer.

## 2. Capacity and initial state

`Capacity` is a positive compile-time constant.

Zero-capacity instantiations are rejected rather than introducing a special
representation or sentinel semantics.

`.init` is a valid empty vector:

```text
length == 0
empty == true
full == false
capacity == Capacity
```

No allocation occurs when the vector is created, used, cleared or destroyed,
apart from behavior performed by T itself.

## 3. Stable candidate surface

The promotion candidate surface is deliberately small:

```d
enum size_t capacity;

@property size_t length() const;
@property bool empty() const;
@property bool full() const;

ref T front();
ref const(T) front() const;

ref T back();
ref const(T) back() const;

ref T opIndex(size_t index);
ref const(T) opIndex(size_t index) const;

T[] opSlice();
const(T)[] opSlice() const;

void pushBack(...);
bool tryPushBack(...);

void popBack();
void clear();
```

No reserve/growth API exists because capacity cannot change.

No allocator/storage policy parameter is part of the public type.

## 4. Slice syntax

The stable candidate uses D slice syntax:

```d
auto live = vector[];
```

rather than introducing `asSlice` as an independent permanent spelling.

The returned slice covers exactly the live prefix:

```text
vector[][0 .. vector.length]
```

and aliases the vector's inline storage.

The slice is a borrow:
- it must not outlive the vector;
- structural mutation may invalidate assumptions about which elements are live;
- moving or destroying the vector invalidates outstanding borrows.

DIP1000 negative compile tests must reject escaping a slice borrowed from a
local vector.

## 5. Access preconditions

`front` and `back` require `!empty`.

Indexed access requires:

```text
index < length
```

`popBack` requires `!empty`.

These are programming preconditions, matching normal low-level container
practice. They are not recoverable runtime error channels.

## 6. Insertion

Two insertion forms are candidates:

### pushBack

`pushBack(value)` is the precondition-based hot-path primitive.

Precondition:

```text
length < capacity
```

It does not overwrite an existing element.

The operation begins one T lifetime in the next unused slot, then increments
length.

### tryPushBack

`tryPushBack(value)` is the checked form.

If full:
- returns false;
- does not mutate the vector;
- does not begin/end an element lifetime.

Otherwise it performs the same insertion and returns true.

This preserves the existing containers-d convention of an explicit
non-overwriting checked insertion while also admitting a branch-free
precondition path for consumers such as exact expansion arithmetic.

## 7. Removal and clear

`popBack` ends the lifetime of the final live element and decrements length.

`clear` ends every live element lifetime exactly once and yields an empty
vector. Capacity and inline storage remain present.

For pointer-free trivially destructible T, the implementation may reduce
`clear` to assigning length zero.

For indirection-bearing T, vacated storage must not retain stale GC roots.

## 8. Contiguity

Live elements are contiguous and ordered in insertion order.

For every non-empty vector:

```text
&vector[0] == vector[].ptr
vector[].length == vector.length
```

The implementation may reserve hidden alignment slack outside the live element
span when required by compiler/platform alignment behavior.

Such slack is not observable through the element slice.

## 9. Alignment and GC visibility

The M4.2 inline-storage qualification remains part of the StaticVector
contract:

- every live T address satisfies T.alignof;
- over-aligned T remains correct even when the vector is embedded in another
  aggregate on DMD 2.111;
- GC-visible indirections in live elements remain reachable;
- bytes of vacated indirection-bearing slots are sanitized as required;
- storage representation does not implicitly own T lifetimes.

## 10. Element-type policy

The first promoted type must support at least:

- scalar/POD-like T;
- ordinary copyable structs;
- structs with elaborate destruction;
- move-only structs with qualified language move construction;
- indirection-bearing values.

Nested/local structs with hidden context/indirections remain rejected while the
existing lifetime issue is unresolved. Promotion must not silently broaden that
contract.

## 11. Copy semantics

Because storage is inline, copying a StaticVector does not require backing
allocation.

For copy-constructible T:
- destination length equals source length;
- each live source element is copy-constructed into the corresponding
  destination slot;
- inactive slots do not become live objects.

If T is not copy-constructible, StaticVector copy construction is disabled.

Copy must not accidentally alias container-owned storage.

## 12. Move semantics

Moving a StaticVector relocates its live elements because inline storage moves
with the aggregate.

For T with language move construction, the qualified placement-move operation
is used so the object is constructed at its final destination address.

The moved-from vector becomes empty after a successful nontrivial move.

Self-referential element types therefore depend on T's own move semantics; raw
byte relocation is not substituted for a required language move operation.

## 13. Assignment

Identity assignment for element types requiring custom lifetime transfer is not
part of the initial promotion contract until self-assignment, destination
cleanup and exception/error guarantees are separately qualified.

The public type must not silently inherit an unsafe/incorrect aggregate
assignment path.

## 14. Attributes

Operations should preserve:

```text
@safe
@nogc
nothrow
pure
```

whenever the required T operation and the current frontend permit them.

In particular, move safety is compiler-qualified. Frontend 2.111 accepts some
`__rvalue(local)` move expressions from `@safe` code that frontend 2.112+
rejects independently of the element move constructor's own annotation.
containers-d must follow that frontend capability and must never upgrade a
rejected move path to `@safe` through an internal trusted bridge.

The binary64 consumer gate specifically requires its hot surface to remain:

```d
pure nothrow @safe @nogc
```

Attribute claims are executable gates, not documentation-only promises.

## 15. Performance contract

The container does not promise a particular instruction sequence.

Promotion does require that the generic family introduce no material regression
against the consumer-local fixed-buffer baseline on the controlled compiler
matrix.

Qualified evidence already shows:
- effectively zero-cost direct mechanics on DMD 2.111 and LDC 1.41;
- real geo-d DMD hot paths instruction-identical when mechanics are composed in
  consumer scope;
- independent geo3-d DMD paths instruction-identical, including larger
  intermediate capacities;
- only tiny reproducible LDC code-shape differences in one expansion-sum path.

These measurements justify the family architecture, not compiler-specific
public policy switches.

## 16. Advanced composition is not stable API yet

The research-only `ScalarStaticVectorOps` mixin demonstrated that consumer
scope code generation can avoid DMD wrapper/module penalties.

That does not by itself justify a stable public customization mechanism.

geo-d and geo3-d are independent consumers but exercise materially the same
scalar fixed-vector adaptation.

Until a materially different real consumer needs the same composition
mechanism:
- the mixin remains research/internal;
- its name and shape are not compatibility promises;
- the stable public contract is the StaticVector type itself.

## 17. Promotion gates

Before package-root export:

- candidate stable import module;
- positive external consumer;
- DMD 2.111 and LDC 1.41 unit/release/docs builds;
- DIP1000 positive consumer;
- DIP1000 slice/reference escape negative tests;
- copyable/move-only/destructor/GC element matrix;
- over-alignment regression coverage;
- adversarial reference-model sequence test;
- direct and algorithm performance probes remain qualified;
- template-instantiation compile-time measurement;
- representative binary/object-size measurement;
- documentation clearly separates stable type API from research composition.

Only after all gates pass should `module containers` re-export StaticVector.
