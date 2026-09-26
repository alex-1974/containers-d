# containers-d

High-performance generic container primitives for D.

Status: pre-release.

## Initial focus

The first container family is the ring buffer.

The design will distinguish container types by their actual storage and
concurrency semantics rather than hiding materially different behaviour behind
one type.

Initial areas of investigation include:

- fixed-capacity inline ring buffers;
- runtime-capacity ring buffers;
- FIFO queues;
- LIFO/FILO stacks;
- storage and lifetime policies;
- allocation-free steady-state operation;
- contiguous segment access for wrapped storage;
- explicit overflow behaviour;
- safe and measurable high-performance implementations.

Concurrent SPSC/MPMC structures are not assumed to share the same contract as
ordinary single-threaded containers and will be designed separately if added.

See `ROADMAP.md` and `docs/design/`.
