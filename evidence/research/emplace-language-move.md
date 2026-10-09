# core.lifetime.emplace with language-move rvalues

Tracking: issue #8  
Research branch: `research/move-constructor-elements`

## Question

Does `core.lifetime.emplace(target, __rvalue(source))` preserve the D language
move-constructor contract for a struct that defines `this(T)`?

## Existing executable evidence

The original raw-storage research run was:

```text
Move Constructor Research
run 36310582185
```

Qualified compilers:

- DMD 2.111.0
- DMD 2.113.0
- LDC 1.41.0
- LDC 1.43.0

All four jobs completed successfully as research harness jobs.

Observed common result for `emplace(target, __rvalue(source))`:

- `__traits(hasMoveConstructor, T) == true`;
- move-constructor count remains zero;
- target receives the scalar payload;
- a self-referential target is invalid because its internal pointer still
  refers to source storage rather than the target object.

Direct move construction and placement new both invoke `T.this(T)` and repair
the self-reference on the same matrix.

## Source-state divergence

The original probe also recorded different moved-from source states:

- DMD 2.111.0 / 2.113.0 reset the tested destructor-bearing source to its
  initializer state;
- LDC 1.41.0 / 1.43.0 left the same source payload observable.

This divergence is not needed to establish the emplace construction defect.

A follow-up standalone probe under
`experiments/emplace_language_move/` separates:

- direct language move construction;
- `forward` + assignment;
- emplace with a non-destructor type;
- emplace with a destructor-bearing type;
- the self-referential invariant case.

A six-version workflow covers DMD 2.111.0 / 2.112.1 / 2.113.0 and
LDC 1.41.0 / 1.42.0 / 1.43.0. This additional matrix is diagnostic evidence;
the classification below does not depend on the source-state difference.

## Public contract

The public `core.lifetime.emplace` documentation says that it constructs an
object of type T at the supplied address from `args`. It also describes
safety in terms of the corresponding constructor.

D language move-constructor semantics select `this(T)` for rvalue
construction. Direct:

```d
T target = __rvalue(source);
```

does invoke the move constructor in the qualified matrix.

Therefore an emplace operation that presents itself as construction from the
same rvalue argument is expected to preserve construction invariants rather
than silently use ordinary assignment semantics.

## druntime implementation

The relevant `core.internal.lifetime.emplaceRef` implementation is materially
the same in DMD/druntime 2.111.0, 2.113.0, and current master.

The general runtime branch creates an internal wrapper with a payload field and
prefers assignment whenever it compiles:

```d
static struct S
{
    T payload;

    this()(auto ref Args args)
    {
        static if (__traits(compiles, payload = forward!args))
            payload = forward!args;
        else
            payload = T(forward!args);
    }
}
```

For the tested language-move type, the assignment expression compiles, so the
constructor expression is not selected. Ordinary assignment does not dispatch
the struct language move constructor. The result can therefore violate
invariants that `this(T)` exists specifically to establish at the final
address.

## Upstream search

No exact upstream duplicate was found.

Related:

- dlang/dmd#20950: placement new does not select an *implicit copy
  constructor*. This is a different mechanism and failure.
- dlang/dmd#17219: unrelated `emplace` qualifier/safety problem.
- dlang/dmd#20442: broader proposal around move/forward intrinsics, not this
  construction-contract bug.

## Classification

**DRUNTIME / library contract defect**, compiler-independent for the core
finding.

The defect is not that DMD and LDC leave the source in different observable
states. The defect is that `core.lifetime.emplace` chooses an assignment path
that bypasses a user-defined language move constructor and can produce an
invalid final object.

The source-state divergence is secondary compiler/backend behavior in the
forwarding path and is not part of the containers-d production contract.

## containers-d decision

No production change is required.

containers-d already avoids `core.lifetime.emplace` for an exact-T rvalue when
T defines a D language move constructor. It uses audited placement construction
at the final slot address instead.

Do not replace that path with `emplace` until upstream semantics change and
are requalified.

## Upstream report status

A complete upstream report was prepared with a standalone reproducer and source
analysis. The connected GitHub integration cannot create issues in
`dlang/dmd` and returned:

```text
403 Resource not accessible by integration
```

Accordingly:

- no upstream issue number is claimed;
- this finding must not yet be promoted into workspace `TOOLCHAIN_ISSUES.md`
  as a reported defect;
- administrative upstream submission remains external to this research result.
