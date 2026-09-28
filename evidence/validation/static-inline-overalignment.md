# Static inline over-alignment probe

Status: research finding; correction tracked by issue #31  
Baseline compilers: DMD 2.111.0, LDC 1.41.0

## Question

Does the current StaticRingBuffer representation provide a type-level alignment
guarantee for an over-aligned element when the buffer is embedded inside another
aggregate?

This is stronger than checking the address of one standalone stack variable.

Probe:

`benchmarks/static_ring_alignment_probe.d`

Workflow:

`.github/workflows/probe-static-ring-alignment.yml`

Test element:

```d
align(64) struct OverAligned64
{
    ulong value;
}
```

The probe reports:

- T.alignof;
- StaticRingBuffer.alignof;
- offset of an embedded StaticRingBuffer field;
- InlineRawStorage prototype alignof;
- offset of an embedded InlineRawStorage field.

## DMD 2.111 result

```text
element-align 64
ring-align 8
ring-holder-offset 8
ring-sufficient 0
storage-align 1
storage-holder-offset 1
storage-slot-address-mod-element-align 0
storage-slot-sufficient 1
```

The current StaticRingBuffer type reports only alignment 8 and is embedded at
offset 8, so its released representation does not provide the required
type-level guarantee.

An intermediate InlineRawStorage experiment also showed that merely increasing
the wrapper type's `.alignof` was insufficient: DMD could still embed that
wrapper at the default field alignment.

The current research candidate therefore no longer relies on wrapper
over-alignment. For T.alignof greater than native pointer alignment it reserves
T.alignof - 1 bytes of inline slack and derives the slot base from the actual
runtime address. Its wrapper may have alignof 1 and be embedded at offset 1,
while the actual T slot remains exactly 64-byte aligned.

## LDC 1.41 result

```text
element-align 64
ring-align 64
ring-holder-offset 64
ring-sufficient 1
storage-align 1
storage-holder-offset 1
storage-slot-address-mod-element-align 0
storage-slot-sufficient 1
```

LDC already propagates the current StaticRingBuffer over-alignment correctly.
The portable InlineRawStorage candidate nevertheless uses the same
runtime-aligned-slot representation as DMD for over-aligned T so its correctness
does not depend on compiler-specific aggregate embedding behavior.

## Existing test limitation

The current StaticRingBuffer unittest checks the address of one standalone
`align(32)` buffer instance.

That test can pass because of the concrete stack placement even when the
container type does not provide a sufficient embedding alignment guarantee.

The deterministic holder-offset probe is therefore the stronger test for this
contract.

## Consequence for M4.2

The current reusable InlineRawStorage prototype now demonstrates the first
cross-compiler representation that finds an aligned inline slot base
independently of the enclosing object's alignment.

For over-aligned T with GC-visible indirections it cannot reuse an exact
T[Capacity] pointer bitmap because slot zero may be shifted at runtime. The
candidate therefore overlays the raw payload with a conservative pointer-word
scan shape and zero-initializes the whole GC-visible payload.

A dedicated GC integration test places InlineRawStorage for an align(64) struct
containing a class reference inside a GC-heap-resident holder. On both DMD
2.111 and LDC 1.41 the referent remains reachable while stored and becomes
collectible after the slot lifetime ends and clearVacatedSlot() zeros the slot.

This makes the representation a viable candidate for issue #31 and future
StaticVector research, but StaticRingBuffer is not switched to it until
whole-container performance and layout effects are independently qualified.

## References

- D language align attribute: the specification describes alignment for fields
  and aggregate types and states that aggregate natural alignment derives from
  its fields.
- D union rules: unions do not automatically destroy union fields, which is
  relied upon by the raw-storage scan-shape overlay.

This finding is tracked separately from M4.2 factoring because it concerns a
released StaticRingBuffer correctness contract.
