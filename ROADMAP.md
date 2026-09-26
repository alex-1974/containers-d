# containers-d Roadmap

This repository follows the canonical workspace engineering contract under
`.workspace/`.

## M0 — Repository foundation

- establish repository structure;
- establish Fast CI and Release Gate;
- establish package and evidence boundaries;
- establish the first ring-buffer design contract.

## M1 — Ring-buffer semantic core

- define invariants;
- define element-lifetime semantics;
- define fixed versus runtime capacity;
- define overflow semantics;
- define observable allocation behaviour;
- define storage layout and alignment requirements;
- define safe access and mutation API;
- define wrapped-storage segment access;
- establish correctness and adversarial tests.

## M2 — Fixed-capacity ring buffer

- inline storage;
- compile-time capacity;
- no heap allocation;
- allocation-free steady-state operations;
- validate generated code and hot-path costs.

## M3 — Runtime-capacity ring buffer

- explicit one-time storage acquisition;
- no hidden allocation during steady-state operations;
- allocator/lifetime model;
- move/copy/destruction correctness.

## Later candidates

- FIFO queues;
- LIFO/FILO stacks;
- deque-like structures where justified;
- SPSC ring buffers;
- other bounded container primitives.

Later milestones are admitted only when their contracts and consumer need are
clear.
