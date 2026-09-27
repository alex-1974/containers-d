# Raw-storage move-constructor research

Issue: #3.

This experiment separates three mechanisms that can otherwise be conflated:

1. D language move construction (`this(T)`, introduced/enabled in D 2.111);
2. placement construction through `core.lifetime.emplace`;
3. destructive relocation through `core.lifetime.moveEmplace` and
   `opPostMove`.

The experiment is deliberately outside the public package source. It does not
change the admitted `StaticRingBuffer` contract.

## Questions

- Does `emplace(target, __rvalue(source))` dispatch a language move
  constructor into uninitialized storage?
- Does `moveEmplace` dispatch it?
- What happens to a self-referential element under each path?
- Does the classic `opPostMove` relocation contract repair internal pointers?
- Are DMD and LDC frontend-compatible on the workspace baseline?
- Have newer canary compilers changed the behavior?

## Matrix

Decision baselines:

- DMD 2.111.0
- LDC 1.41.0 (DMD frontend 2.111)

Informational canaries:

- DMD 2.113.0
- LDC 1.43.0

A result is not treated as a toolchain defect until it is compared with the
language specification and the documented contract of the druntime primitive.
