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
storage-align 64
storage-holder-offset 8
storage-sufficient 0
```

Two separate facts matter:

1. the current StaticRingBuffer type itself reports only alignment 8;
2. even the research InlineRawStorage type, after being given alignof 64, is
   placed at offset 8 when embedded in a default-aligned holder.

Therefore merely increasing the nested storage type's `.alignof` is not a
sufficient DMD-2.111 solution.

## LDC 1.41 result

```text
element-align 64
ring-align 64
ring-holder-offset 64
ring-sufficient 1
storage-align 64
storage-holder-offset 64
storage-sufficient 1
```

LDC propagates the over-alignment through both tested aggregate layers.

## Existing test limitation

The current StaticRingBuffer unittest checks the address of one standalone
`align(32)` buffer instance.

That test can pass because of the concrete stack placement even when the
container type does not provide a sufficient embedding alignment guarantee.

The deterministic holder-offset probe is therefore the stronger test for this
contract.

## Consequence for M4.2

The reusable InlineRawStorage prototype is not yet admissible as the production
foundation for arbitrary over-aligned T on both baseline compilers.

M4.2 can continue to use it for contract/layout research, but production
promotion requires issue #31 to resolve one of the following:

- a representation that finds an aligned inline slot base independent of the
  enclosing object's base alignment;
- a proven compiler-qualified supported-alignment bound;
- another mechanism with equivalent correctness.

For indirection-bearing T, any dynamically shifted slot base must also preserve
GC visibility of all possible pointer locations.

## References

- D language align attribute: the specification describes alignment for fields
  and aggregate types and states that aggregate natural alignment derives from
  its fields.
- D union rules: unions do not automatically destroy union fields, which is
  relied upon by the raw-storage scan-shape overlay.

This finding is tracked separately from M4.2 factoring because it concerns a
released StaticRingBuffer correctness contract.
