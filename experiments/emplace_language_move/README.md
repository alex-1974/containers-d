# core.lifetime.emplace language-move reproducer

Tracking: issue #8.

This standalone probe isolates the unresolved observation from the earlier
raw-storage move-constructor research.

It compares:

1. direct D language move construction with `__rvalue`;
2. assignment through `core.lifetime.forward`, mirroring the assignment-first
   branch used by `core.internal.lifetime.emplaceRef`;
3. `core.lifetime.emplace(target, __rvalue(source))` without a destructor;
4. the same operation when T has a destructor;
5. a self-referential T whose move constructor repairs its internal pointer.

The probe imports no containers-d module.

The qualification matrix is the supported release family:

- DMD 2.111.0
- DMD 2.112.1
- DMD 2.113.0
- LDC 1.41.0
- LDC 1.42.0
- LDC 1.43.0

The probe records behavior; it does not treat a difference as an upstream bug
until the public `emplace` contract and its druntime implementation have been
compared.
