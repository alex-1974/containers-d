# Raw-storage language move construction

Promoted finding from issue #3 research.

## Matrix

Decision baselines:

- DMD 2.111.0
- LDC 1.41.0

Informational canaries:

- DMD 2.113.0
- LDC 1.43.0

## Finding

For a type defining `this(T)`:

- direct language move construction invokes the move constructor;
- `core.lifetime.moveEmplace` does not invoke it;
- D 2.111 placement new with `__rvalue` invokes it exactly once at the final
  raw-storage address on all four tested compilers.

A self-referential regression type confirmed that placement-new move
construction repairs its internal pointer to the destination object, while
plain relocation without `opPostMove` does not.

For types without a language move constructor, `moveEmplace` remains the
appropriate classic relocation primitive and correctly invokes `opPostMove`
when present.

## Decision

`StaticRingBuffer` selects the primitive semantically:

```text
hasMoveConstructor(T)
    -> placement new T(__rvalue(source))
otherwise
    -> moveEmplace(source, target)
```

Placement new is not allowed directly in `@safe` code. The implementation
therefore uses the smallest possible trust boundary and only marks that boundary
trusted when ordinary move construction of `T` is independently safe.

The separate behavior of `core.lifetime.emplace(target, __rvalue(source))` is
not relied upon by the container and is tracked in issue #8.
