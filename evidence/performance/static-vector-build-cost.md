# StaticVector build-cost qualification

Status: qualified promotion evidence  
Tracking: issue #34  
Baseline compilers: DMD 2.111.0, LDC 1.41.0

## Question

Does the generic StaticVector promotion candidate impose material compile-time
or generated-code cost compared with a direct fixed-array implementation?

Runtime performance is qualified separately. This probe measures:
- one-process compile elapsed time;
- compiler peak RSS;
- object-file bytes;
- ELF text/data/bss reported by `size`.

Timing is observational because GitHub-hosted runner scheduling/noise can affect
small absolute durations. Object/section sizes are the stronger deterministic
signal.

## Probe shape

Measured capacities:

```text
1, 2, 3, 4, 8, 16, 32, 64
```

Each source emits the same family of externally visible checksum functions.

Three variants are compared:

### minimal

A consumer-local fixed vector containing only:
- inline `ulong[N]`;
- logical length;
- pushBack;
- indexed access.

This is useful as a lower-bound but does **not** match the public API width.

### matched

A direct `ulong[N] + length` implementation with the full StaticVector
promotion surface:
- capacity/length/empty/full;
- front/back;
- mutable/const index;
- mutable/const slice;
- pushBack/tryPushBack;
- popBack;
- clear.

This is the fair API-width baseline.

### candidate

`containers.static_vector.StaticVector!(ulong, N)`.

The candidate automatically selects its scalar direct-storage specialization;
no allocator/policy switch is exposed.

## Why the first comparison looked too expensive

An earlier probe compared StaticVector only with the minimal two-operation
baseline.

DMD emitted the instantiated candidate's additional public methods
(`front/back`, slices, `tryPushBack`, etc.), so the object-size difference
mostly measured API breadth rather than generic-container overhead.

Symbol evidence confirmed this directly.

The promotion probe therefore retains the minimal lower bound but bases the
generic-overhead decision on `matched ↔ candidate`.

## Final DMD 2.111 result

| Variant | Elapsed s | Peak RSS KiB | Object bytes | text | data | bss |
|---|---:|---:|---:|---:|---:|---:|
| minimal | 0.09 | 20,932 | 31,548 | 9,308 | 1,696 | 1,048 |
| matched | 0.10 | 22,316 | 77,264 | 13,016 | 1,696 | 1,048 |
| candidate | 0.10 | 25,968 | 71,116 | 12,472 | 1,696 | 1,048 |

Relative to the API-matched direct implementation, the candidate is:
- 6,148 bytes smaller (-7.96%);
- 544 text bytes smaller (-4.18%);
- equal in the observed 0.10 s compile-time sample;
- about 3.6 MiB higher peak compiler RSS.

## Final LDC 1.41 result

| Variant | Elapsed s | Peak RSS KiB | Object bytes | text | data | bss |
|---|---:|---:|---:|---:|---:|---:|
| minimal | 0.07 | 100,636 | 18,200 | 5,255 | 52 | 0 |
| matched | 0.13 | 104,916 | 53,000 | 8,378 | 52 | 0 |
| candidate | 0.11 | 107,940 | 48,048 | 7,928 | 52 | 0 |

Relative to the API-matched direct implementation, the candidate is:
- 4,952 bytes smaller (-9.34%);
- 450 text bytes smaller (-5.37%);
- slightly faster in this observed sample (0.11 versus 0.13 s);
- about 3.0 MiB higher peak compiler RSS.

## Internal specialization lesson

The first generic StaticVector used the complete raw-slot/lifetime machinery
even for scalar T. It was runtime-neutral but unnecessarily expensive to
compile.

The admitted promotion candidate now specializes automatically:

```text
scalar T
    -> direct T[N] storage
    -> direct by-value push
    -> no lifetime/raw-slot mixin instantiation

non-scalar T
    -> audited InlineRawStorageOps
    -> element lifetime operations
    -> GC/alignment handling where required
```

This is an internal implementation choice, not a user policy.

A second refinement removed private scalar `slotPointer`/`slotSlice`
helpers and generated public scalar accessors directly over `T[N]`. That
brought candidate object/text size below the API-matched direct baseline.

## Decision

The build-cost gate is passed for the controlled DMD 2.111 / LDC 1.41
promotion baseline.

No hard compile-time percentage is adopted from sub-second hosted-runner timing.
The evidence instead establishes that:
- candidate object/text size is not inflated versus an API-equivalent direct
  implementation;
- absolute compile times remain small in this representative instantiation set;
- peak compiler RSS is modestly higher and should remain observable in future
  family growth.

The scalar specialization remains automatic and private.
