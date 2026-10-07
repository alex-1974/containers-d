# M6 ScratchBuffer contract research

Status: Stage 1 active research  
Tracking: issue #27  
Baseline: post-M5 develop

## Research question

Does containers-d need a reusable contiguous typed scratch family, and if so,
what is the smallest semantic contract that serves repeated real-consumer
patterns without becoming a general allocation/resource framework?

M6 begins with ScratchBuffer only. Arena, BufferPool and UniqueBuffer remain
separate questions.

## Stage 1 semantic baseline

The first prototype is:

```d
ResearchScratchBuffer!T
```

with one backing allocation established at construction.

Observable Stage-1 semantics:

- `.init` is inert with capacity/length zero;
- runtime capacity is fixed after construction;
- storage is uniquely owned and movable in O(1);
- copy/assignment are disabled;
- exactly `length` elements are live;
- live elements occupy the contiguous prefix;
- `buffer[]` borrows exactly that live prefix;
- `tryPushBack` appends only when established capacity is available;
- full insertion returns false and performs no allocation;
- `reset()` ends all live T lifetimes and retains the backing allocation;
- successful reuse after reset uses the same backing address;
- `highWater` is research telemetry for workload characterization;
- destruction resets live elements before releasing storage.

## Why Stage 1 does not grow

Live reallocation is deliberately excluded from the first experiment.

A growing typed owner must decide:

- whether every live T is copied or moved;
- how failure behaves after partial relocation;
- whether self-referential move constructors are supported;
- when existing borrows become invalid;
- whether capacity growth is geometric, exact, caller-directed or policy-driven;
- whether shrink is ever automatic;
- whether a generic UniqueBuffer owner should exist underneath.

Those are separate contract decisions. They must not be smuggled into
ScratchBuffer merely because vector-like growth is familiar.

Stage 1 instead asks the simpler consumer-relevant question:

> once enough scratch capacity has been established, is retained reusable
> contiguous storage useful and zero/low overhead?

A later Stage 2 may add **empty-only capacity re-establishment** first. Live
growth is admitted only if real consumers require it.

## Ownership and borrowing

The prototype owns its one backing allocation.

Borrowed slices:

- do not own storage;
- are valid only while the owner remains at the same identity and the relevant
  live prefix remains unchanged;
- are invalidated by structural mutation, reset, whole-buffer move or
  destruction.

The first family is thread-confined. Cross-thread pooling is not part of the
ScratchBuffer contract.

## Element lifetime

The implementation reuses the qualified package-internal M4 mechanisms:

- RuntimeStorageOwner for aligned runtime backing storage and GC registration;
- PlacementMoveOps for language-move placement where qualified;
- EndElementLifetimeOps for explicit lifetime end;
- vacated-slot clearing for GC-visible indirections.

This is important evidence for #26: Stage 1 does **not** require a new public
UniqueBuffer type merely to obtain correct aligned ownership.

It remains possible that a later common owner extraction is justified, but M6
will demand evidence before introducing it.

## Candidate use classes

### DCanvas-style temporary typed arrays

Expected pattern:

```text
establish capacity
repeat:
    reset
    append temporary values
    process borrowed live slice
```

The hot repeated phase should not allocate.

### Geometry orchestration scratch

Caller-owned slice APIs remain preferred at algorithm boundaries.

ScratchBuffer, if promoted, would be an optional owner at a higher layer that
can repeatedly supply those slices. It must not replace caller-workspace APIs.

### OSM / raster reusable workspace

Expected pattern:

```text
worker owns buffer
capacity retained across records/tiles
logical contents reset
same allocation reused
```

Cross-thread pool ownership remains a separate BufferPool question.

## Stage 1 gates

Correctness:

- repeated reset/reuse retains capacity and backing address;
- destructor-bearing T lifetimes end exactly once;
- over-aligned T remains correctly aligned;
- indirection-bearing T uses GC-visible storage and vacated-slot sanitation;
- O(1) whole-owner move preserves live element addresses;
- copy and assignment stay rejected;
- full insertion does not allocate or overwrite;
- borrowed slice is the exact live prefix.

Attributes:

- trivial-T construction and steady-state append/reset/slice usage qualify for
  `@safe @nogc nothrow` on baseline compilers.

Performance:

- compare the candidate against a manual preallocated contiguous array +
  logical-length baseline with identical semantics;
- setup/allocation occurs outside the measured repeated-use loop;
- measure DMD 2.111 and LDC 1.41 retired instructions;
- investigate any material abstraction overhead before expanding the API.

## Stage 2 questions

Only after Stage 1:

1. Is empty-only capacity re-establishment sufficient for real workloads?
2. Is a separate UniqueBuffer owner useful under both RingBuffer and
   ScratchBuffer, or would extraction add abstraction cost/contract surface?
3. Do any consumers require preserving live contents while capacity grows?
4. Is high-water accounting useful public behavior or research telemetry only?
5. Should a production type expose vector vocabulary or scratch-specific
   reset/reuse vocabulary?

## Explicit non-goals

- heterogeneous Arena allocation;
- cross-thread BufferPool;
- object pooling;
- automatic shrink;
- custom release callbacks;
- raster resource provenance;
- universal allocator/storage policy templates;
- consumer-repository migration during this research.
