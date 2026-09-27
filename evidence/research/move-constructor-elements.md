# Language move constructors in raw storage

Issue: #3  
Research branch: `research/move-constructor-elements`

## Question

How should `StaticRingBuffer` move a live element from one inline raw-storage
slot to another when the element defines a D language move constructor
(`this(T)`)?

The admitted implementation initially disabled whole-buffer move construction
for such element types because `core.lifetime.moveEmplace` does not dispatch
the language move constructor.

## Sources and semantics

D 2.111 introduced/enabled:

- D language move constructors selected for rvalue construction;
- `__rvalue`;
- placement-new expressions.

Placement new starts a new object lifetime in caller-provided storage and uses
normal language construction semantics. It is not allowed directly in `@safe`
code, so a generic container must keep it behind a narrow audited
`@trusted` boundary.

`core.lifetime.moveEmplace` is a different abstraction. Its implementation
performs destructive relocation and uses `opPostMove` for types requiring
post-relocation repair. It does not query `__traits(hasMoveConstructor, T)`
and does not dispatch `this(T)`.

## Matrix

Decision baselines:

- DMD 2.111.0
- LDC 1.41.0

Informational canaries:

- DMD 2.113.0
- LDC 1.43.0

All four research jobs passed.

## Results

### Direct language move

All four compilers:

```text
moves=1
copies=0
source moved to benign state
target receives value
```

### `moveEmplace` with a language-move-constructor type

All four compilers:

```text
moves=0
copies=0
```

The language move constructor is not called.

For a self-referential type without `opPostMove`, the relocated target retains
an internal pointer into the source object and is therefore invalid.

This confirms that `moveEmplace` must not be used as a substitute for a
language move constructor.

### `moveEmplace` with classic `opPostMove`

All four compilers:

```text
opPostMove=1
target self-pointer valid
```

This is the correct mechanism for the classic destructive-relocation category.

### Placement new with `__rvalue`

Probe form:

```d
auto placed = new (*target) T(__rvalue(source));
```

All four compilers:

```text
moves=1
copies=0
placed is target
source moved to benign state
```

For the self-referential test type:

```text
moves=1
source self-pointer cleared
target self-pointer points to target storage
```

Placement new therefore preserves the element's language move-constructor
contract at the final raw-storage address.

## Separate `emplace` finding

`core.lifetime.emplace(target, __rvalue(source))` did **not** invoke the
language move constructor in any tested compiler.

Additionally, DMD 2.111/2.113 and LDC 1.41/1.43 differed in the observed
moved-from source state for that path.

This finding is not needed for the ring-buffer solution and should be tracked
separately before any upstream defect claim is made.

## Decision

For `StaticRingBuffer` whole-buffer move construction:

```text
if T has a D language move constructor:
    placement-new T(__rvalue(source)) into the final destination slot
else:
    use core.lifetime.moveEmplace for classic destructive relocation
```

After successful construction/relocation, explicitly end the moved-from source
slot lifetime and remove it from the source buffer's live-slot accounting.

Placement new is wrapped in the smallest possible `@trusted` helper. The
helper's proof obligation is:

- destination points to correctly aligned, uninitialized storage for one T;
- source is a distinct live T;
- the language move constructor is selected by `__rvalue(source)`;
- destination lifetime begins exactly once;
- caller ends the moved-from source lifetime exactly once.

## No toolchain workaround

The ring-buffer implementation does not need a compiler-version workaround or
a custom byte-level relocation primitive.

The language feature introduced at the workspace minimum frontend (2.111) is
sufficient and behaves consistently on both baseline compilers.
