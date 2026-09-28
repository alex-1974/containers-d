# M4.3 — StaticVector family proof

Status: active research  
Tracking: issue #25  
Parent: issue #23  
Foundation: M4.2 / issue #29

## Goal

Determine whether containers-d can provide a generic fixed-capacity contiguous
vector family without weakening the properties of the duplicated
`ExpansionBuffer!Capacity` implementations currently maintained by geo-d and
geo3-d.

This is a proof milestone, not yet a public API commitment.

## Hard consumer baseline

Both geo-d and geo3-d independently implement the same essential shape:

```d
struct ExpansionBuffer(size_t Capacity)
if (Capacity > 0)
{
    double[Capacity] _data;
    size_t _length;

    enum size_t capacity = Capacity;

    @property size_t length() const
        pure nothrow @safe @nogc;

    @property bool empty() const
        pure nothrow @safe @nogc;

    void clear()
        pure nothrow @safe @nogc;

    void append(double value)
        pure nothrow @safe @nogc;

    double opIndex(size_t index) const
        pure nothrow @safe @nogc;
}
```

The current source uses small capacities heavily. The expansion modules contain
explicit instantiations at capacities 1, 2, 3 and 4.

Therefore the first StaticVector proof must preserve:

- fixed inline capacity;
- inert empty `.init`;
- no container allocation;
- contiguous storage;
- O(1) append/index/back removal;
- the `pure nothrow @safe @nogc` binary64 hot path;
- compact layout;
- no measurable hot-path regression on DMD 2.111 or LDC 1.41.

## Research type

The first prototype is package-internal:

```d
containers.internal.static_vector.StaticVector!(T, Capacity)
```

It is intentionally not re-exported from `containers`.

Current research surface:

- `capacity`;
- `length`;
- `empty`;
- `full`;
- `front`;
- `back`;
- indexed access;
- borrowed live-prefix slice;
- precondition-based `pushBack`;
- checked `tryPushBack`;
- `popBack`;
- `clear`.

The precondition-based push primitive is deliberate. Exact expansion arithmetic
already proves spare capacity through compile-time result-capacity constraints
and local algorithm invariants; it should not pay a runtime full check merely
because a checked convenience API also exists.

## Layering

```text
StaticVector!(T,N)
    |
    +-- logical length / contiguous sequence semantics
    |
    +-- M4.2 element lifetime operations
    |     PlacementMoveOps
    |     EndElementLifetimeOps
    |
    +-- InlineRawStorage!(T,N)
          alignment
          raw slots
          GC visibility
          vacated-slot sanitation
```

StaticVector decides which slots are live. InlineRawStorage owns byte
representation and GC/storage sanitation. The lifetime layer owns D object
construction/destruction transitions.

## Binary64 fast path

For `T == double`:

- no destructor path exists;
- no GC sanitation is required;
- native alignment uses the compact direct-base storage representation;
- clear reduces to `length = 0`;
- object size must remain identical to `double[N] + size_t`.

The prototype currently asserts:

```text
StaticVector!(double,4).sizeof == 40
```

and compiles its basic operations from a:

```d
pure nothrow @safe @nogc
```

probe.

## Nontrivial T research

The prototype also exercises:

- move-only T;
- elaborate destructor T;
- element-wise transfer when raw whole-object transfer would violate T
  semantics;
- stale GC-root cleanup through InlineRawStorage.

This research is secondary to the geo binary64 gate. No nontrivial-T public
contract is frozen by M4.3.

## Copy/move policy under study

For element types that need no elaborate transfer semantics, compiler-generated
whole-StaticVector transfer may remain valid and avoids penalizing trivial
values.

The prototype switches to explicit element-wise copy/move only when T has
relevant nontrivial semantics, including:

- disabled ordinary copy;
- elaborate copy construction;
- elaborate destruction;
- elaborate move/post-move;
- a D language move constructor.

This distinction must be validated before promotion.

## Direct microbenchmark

`benchmarks/static_vector_expansion_probe.d` reproduces the exact
ExpansionBuffer data/API shape locally and compares it with a thin adapter over
StaticVector.

Measured capacities:

```text
1, 2, 3, 4
```

The benchmark:

1. clears the buffer;
2. appends runtime-generated binary64 values;
3. indexes every live component;
4. folds the components into an identical checksum.

It checks:

- identical object sizes;
- identical semantic checksums;
- Callgrind retired instructions on DMD 2.111 and LDC 1.41.

The first measurement is observational. A regression threshold will not be
invented before the baseline data exists.

## Consumer proof sequence

M4.3 proceeds in this order:

1. internal StaticVector contract and unit tests;
2. direct ExpansionBuffer-shape microbenchmark;
3. representative exact-expansion algorithm benchmark;
4. thin wrapper reproducing geo-d/geo3-d ExpansionBuffer API;
5. real geo-d research branch;
6. real geo3-d research branch;
7. only then decide whether StaticVector is ready for a public containers-d
   milestone.

## Promotion gates

StaticVector is not promoted merely because code reuse is attractive.

Required evidence:

- no allocation by the container;
- binary64 contract remains `pure nothrow @safe @nogc`;
- size/layout remains competitive with the local baseline;
- DMD 2.111 and LDC 1.41 show no material hot-path regression;
- representative exact arithmetic remains numerically identical;
- copy/move/destruction tests cover nontrivial T;
- DIP1000 borrowed-slice behavior is qualified;
- over-aligned and indirection-bearing storage remain covered by M4.2 storage
  tests;
- geo-d and geo3-d can retain a domain-specific ExpansionBuffer wrapper if that
  keeps numerical semantics clearer.

## Current decision boundary

Even if this proof succeeds, the likely architecture is:

```text
containers-d
    StaticVector!(T,N)
        |
        +-- generic storage/lifetime/sequence primitive

geo-d / geo3-d
    ExpansionBuffer!N
        |
        +-- numerical domain name/invariants
        +-- thin wrapper or alias over StaticVector!(double,N)
```

The generic family should remove duplicated mechanics, not erase useful
domain vocabulary.
