# Element lifetime termination factoring

Status: qualified research evidence  
Tracking: issue #29  
Baseline compilers: DMD 2.111.0, LDC 1.41.0

## Question

Can the language-level end-of-lifetime operation for a live T object be shared
across container families without changing semantics or adding hot-path cost?

Before M4.2 both ring containers used the same local rule:

```d
static if (hasElaborateDestructor!T)
    destroy!false(*slot);
```

Vacated-slot byte clearing is intentionally excluded from this experiment. It
belongs to the storage layer because its purpose is removal of stale GC-visible
pointer representations from reusable backing storage.

## Factored operation

The research branch introduces the package-internal typed template mixin:

```d
EndElementLifetimeOps!T
```

It injects no state and depends on no host fields. The generated helper receives
a T pointer and:

- calls `destroy!false` when T has an elaborate destructor;
- otherwise performs no language destructor operation.

The helper does not clear or release storage.

## Probe

Benchmark:

`benchmarks/element_lifetime_end_probe.d`

Workflow:

`.github/workflows/perf-element-lifetime-end.yml`

The final probe uses 256 runtime-generated values and 4096 rounds, yielding
1,048,576 construct/destroy cycles per measured variant. Runtime input prevents
the compiler from replacing the workload with a closed-form checksum.

Callgrind collection is toggled only around the selected benchmark function.

The semantic gate requires equal checksums.

## Result

| Compiler | Direct Ir | Mixed Ir | Delta |
|---|---:|---:|---:|
| DMD 2.111.0 | 12,607,518 | 12,607,518 | 0.000000% |
| LDC 1.41.0 | 1,916,957 | 1,916,957 | 0.000000% |

Checksums are identical:

`4275471805041344512`

The first version of this benchmark was rejected as evidence after LDC reduced
its deterministic loop to only 11 measured instructions. The runtime-driven
input version above is the qualified result.

## Integration

Both `StaticRingBuffer` and `RingBuffer` now use
`EndElementLifetimeOps!T` for the language lifetime step.

Their container-local end-slot flow remains responsible for the second step:

```text
end T lifetime
    |
    v
storage-specific clearVacatedSlot
```

For runtime storage, `RuntimeStorageOwner!T.clearVacatedSlot` already owns
this responsibility.

For the current inline StaticRingBuffer storage, equivalent sanitation still
lives locally in the container. Moving that responsibility into a reusable
inline-storage primitive is a separate experiment because changing the inline
storage representation/module boundary may affect generated code and the GC
pointer bitmap.

## Storage contract consequence

M4.2 now distinguishes:

```text
isRawSlotStorage!(S, T)
    capacity
    slotPointer
    slotSlice

isReusableRawSlotStorage!(S, T)
    isRawSlotStorage
    +
    clearVacatedSlot
```

This keeps D object lifetime and backing-storage sanitation independent while
giving future family algorithms a precise reusable-storage capability.

## Decision

The shared lifetime-end mixin is admitted for continued M4.2 research because:

- its semantics match the existing direct operation;
- DMD 2.111 and LDC 1.41 show exact retired-instruction equality in the dedicated
  probe;
- it injects no state and no host-field coupling;
- storage/GC sanitation remains separately owned.

This evidence does not yet justify moving StaticRingBuffer's inline raw storage
into another module. That requires its own layout, GC-bitmap and performance
qualification.
