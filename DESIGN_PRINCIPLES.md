# containers-d Design Specialization

The canonical workspace design principles under
`.workspace/DESIGN_PRINCIPLES.md` remain authoritative.

This file records only containers-d-specific specialization.

## Container semantics are explicit

Materially different storage, ownership, overflow, allocation or concurrency
semantics should be represented explicitly rather than hidden behind one
ambiguous container contract.

## Storage is part of the design

For low-level containers, storage layout, alignment, element lifetime and
allocation behaviour are observable engineering properties and must be
designed and tested deliberately.

## Safety and performance are co-requirements

Performance optimizations must preserve the documented safety and lifetime
contract.

Any required `@trusted` boundary must remain minimal and justified according
to the workspace D practices and quality gates.

## No implicit concurrency contract

Ordinary ring buffers are not automatically thread-safe.

SPSC, MPSC or MPMC structures require separate synchronization and memory-order
contracts and should use distinct types if introduced.
