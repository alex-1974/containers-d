# M8 nested/local element primitive matrix

Tracking: issue #10.

Research branch state qualified by this record:

```text
a4946cd059fd07cb9936ecc168d50a222926f8d6
```

Exact-head GitHub Actions qualification:

```text
M8 Primitive Qualification
run 37891898402
```

All six jobs completed successfully as research harness jobs. A successful job
means the complete matrix was recorded; individual probe runtime failures are
data and are listed below.

## Scope

These probes do not import containers-d.

They compare ordinary typed-storage move construction with placement language
move construction into aligned raw storage for:

- a module-scope control struct;
- a function-local move-bearing struct without an explicit outer-value read;
- a function-local move-bearing struct that reads an enclosing local;
- a function-local move-bearing struct declared in a struct member function
  and reading an explicitly captured pointer to the enclosing aggregate.

The nested forms report `__traits(isNested, T)` and use the same type shape
across trait, ordinary-move, and placement-move probes.

## Reference semantics

The D specification states that `__traits(isNested, T)` is true for a type
that internally stores a context pointer. It also warns that for nested structs
`.init` is not equivalent to normal default initialization because the
context pointer in `.init` is null.

Primary references:

- https://dlang.org/spec/traits.html#isNested
- https://dlang.org/spec/struct.html#nested
- https://dlang.org/spec/property.html#init-vs-default

## Compiler matrix

| Compiler | Frontend basis | Module placement | Local no-capture placement | Local capture placement | Member capture placement |
| --- | --- | --- | --- | --- | --- |
| DMD 2.111.0 | 2.111.0 | PASS | PASS | PASS | PASS |
| DMD 2.112.1 | 2.112.1 | PASS | **SIGSEGV 139** | **SIGSEGV 139** | **SIGSEGV 139** |
| DMD 2.113.0 | 2.113.0 | PASS | **SIGSEGV 139** | **SIGSEGV 139** | runs, but **context corrupt** |
| LDC 1.41.0 | DMD 2.111.0 | PASS | PASS | PASS | PASS |
| LDC 1.42.0 | DMD 2.112.1 | PASS | PASS | PASS | PASS |
| LDC 1.43.0 | DMD 2.113.0 | PASS | PASS | PASS | PASS |

The DMD 2.113 member-capture placement probe completed but produced an invalid
context value instead of the expected `201`:

```text
isNested=true source.value=-1 target.value=42
target.context=734073536 same-address=true
```

The numeric garbage value is not itself a contract; the evidence is that the
captured context was not preserved.

## Stable observations

### Module-scope control

All six compilers agree:

```text
isNested=false
sizeof=4
alignof=4
```

Ordinary and placement construction both run successfully.

This keeps the experiment anchored to a non-context-bearing control.

### Nested move-bearing shape

For the three local/member move-bearing forms, all six compilers report:

```text
isNested=true
sizeof=16
alignof=8
```

on x86_64 in this matrix.

The local-no-capture type is therefore still context-bearing once it has the
same move-bearing type shape as the move probes. "Does not read an outer local"
is not sufficient by itself to treat this shape as a module-scope-equivalent
value.

### Ordinary typed-storage move

All six compilers run the ordinary typed-storage expression successfully.

For example:

```text
LocalValue target = __rvalue(source);
```

The observed source payload remains unchanged in the ordinary-move probes,
whereas the successful placement probes leave the source payload at `-1`
through the user-defined move constructor.

Do not infer from the source payload alone that the two expressions have the
same construction semantics.

### Placement language move

DMD 2.111.0 and all three LDC releases successfully construct the nested value
at the supplied aligned raw-storage address. The successful probes preserve the
captured context and invoke the user move constructor strongly enough to
produce the expected moved-from source payload.

DMD 2.112.1 is the first supported compiler in this matrix where the nested
placement cases fail at runtime.

DMD 2.113.0 retains the failure for the two function-local cases and produces a
corrupt context for the member-frame aggregate-capture case.

The module-scope placement control remains correct on both DMD releases.

## Interpretation

This is **not yet an upstream defect claim**.

It is, however, enough to establish three important M8 facts:

1. the observed failure exists in a primitive placement-new program that does
   not involve containers-d;
2. it begins between DMD 2.111.0 and DMD 2.112.1 in the supported DMD line;
3. LDC 1.42.0 and 1.43.0, despite using the corresponding newer DMD frontend
   bases, do not reproduce the DMD runtime failure.

The third point means the result cannot be described merely as a shared
frontend semantic change. A DMD-specific lowering/code-generation/runtime path
must be investigated before classification.

## containers-d consequence

No production API change follows from this matrix.

v0.2.0 already keeps nested/local context-bearing element support outside the
qualified contract, so the result does not invalidate the released contract.

Before deciding whether containers-d should support, partially support, or
explicitly reject such element types, M8 must still determine the exact
language/toolchain contract and whether a safe zero-cost specialization exists.

## Next probe

Reduce the failing case further before involving container code:

1. one local move-bearing struct;
2. one aligned raw slot;
3. one placement `new (*ptr) T(__rvalue(source))`;
4. instrumentation immediately before and immediately after placement
   construction, without calling `destroy`;
5. a second variant adding destruction only after construction is proven;
6. compare DMD 2.111.0, 2.112.1, 2.113.0 and matching LDC releases;
7. inspect generated code only after the minimal runtime boundary is known.

Only after that reduction should M8 decide whether the result belongs in the
workspace toolchain issue process.
