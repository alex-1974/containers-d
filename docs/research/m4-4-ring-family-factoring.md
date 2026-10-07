# M4.4 — ring-family factoring proof

Status: active research  
Tracking: issue #45  
Baseline: post-StaticVector `develop` at `f5c775d`

## Purpose

This experiment asks whether the two released FIFO ring families can share a
small internal sequencing mechanism without changing their public contracts or
their qualified machine-level behavior.

The experiment is intentionally narrower than a common ring implementation.
Storage, ownership, T lifetime, allocation, borrowing and concurrency remain
family-specific.

## Duplicated mechanics

Both released ring families currently own the same logical state:

```text
head
length
```

and duplicate three sequencing operations:

1. map a logical index to a physical slot;
2. advance the head with wraparound;
3. after a front lifetime has ended, decrement length and either normalize the
   empty state to head zero or advance the head.

The physical-index implementation is not identical:

- StaticRingBuffer has compile-time capacity and retains the measured
  power-of-two mask specialization, otherwise branch/subtract;
- RingBuffer has runtime capacity and retains the M3.3 overflow-safe tail-room
  branch/subtract formulation.

That difference is part of the implementation evidence and is preserved inside
the typed mixin rather than hidden behind runtime policy.

## Candidate internal mechanism

`RingSequenceOps!(StaticCapacity)` is a package-internal typed template mixin.

- positive `StaticCapacity`: compile-time fixed-capacity sequencing;
- zero `StaticCapacity`: runtime-capacity sequencing resolved against the
  consuming aggregate's `capacity` property;
- injects exactly two `size_t` state fields;
- injects no policy object, pointer, allocator, vtable or runtime dispatch;
- knows nothing about element T or storage.

The mixin is generated in the consuming aggregate's scope. This follows the M4.2
evidence that local typed generation can preserve DMD codegen where an ordinary
imported hot helper may not.

## Deliberate exclusions

The experiment does not factor:

- slot storage/access;
- StaticRingBuffer over-alignment handling;
- RuntimeStorageOwner;
- element construction/destruction;
- GC sanitation;
- segment slice provenance;
- copy/move ownership semantics;
- insertion policy;
- public API.

## Qualification

Admission requires all of the following on the experiment branch:

- semantic equivalence of direct and factored sequence probes;
- retired-instruction comparison on DMD 2.111 and LDC 1.41 for:
  - static power-of-two capacity,
  - static non-power-of-two capacity,
  - runtime capacity;
- existing StaticRingBuffer and RingBuffer operation/wraparound probes remain
  green;
- Fast CI and existing lifecycle/GC/DIP1000/consumer gates remain green;
- representative type/layout size remains unchanged.

If any representative production path regresses materially, the experiment must
be rejected or narrowed. A green research result still does not require
production adoption; a later clean promotion would be separate.
