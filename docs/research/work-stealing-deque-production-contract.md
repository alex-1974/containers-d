# Work-stealing deque production contract research

Status: research contract draft  
Tracking: #38  
Consumer request: #39

## Purpose

This document defines the containers-d side of the proposed bounded
single-owner / multi-thief work-stealing deque family.

The consumer request from concurrency-d is evidence for the family, not its
specification. containers-d owns the generic container contract, public API,
supported element model, memory-ordering protocol, implementation strategy and
qualification gates.

The implementation must remain scheduler-independent.

## Architectural position

The work-stealing deque is a distinct concurrent container family.

It is not:

- a thread-safe mode of RingBuffer or StaticRingBuffer;
- a runtime policy applied to an otherwise sequential container;
- a scheduler abstraction;
- an executor queue;
- a universal configurable container.

The intended layering is:

```text
semantic concurrent container family
        |
        v
work-stealing protocol and invariants
        |
        v
compile-time capability selection
        |
        +-- templates / traits / static if
        +-- typed mixin composition where measured and justified
        |
        v
compiler / architecture implementation
```

Known compile-time facts must not become runtime policy or dispatch in the hot
path.

## Consumer boundary

containers-d may model only generic container mechanics.

In scope:

- exactly one owner;
- zero or more concurrent thieves;
- bounded fixed capacity;
- owner-local insertion and removal;
- thief-safe single-item steal;
- thief-safe batch steal;
- deterministic full detection;
- allocation-free steady-state operation;
- supported element representation contract;
- slot publication and reuse;
- atomic index/counter protocol;
- memory ordering;
- cache-line/layout decisions where evidence requires them;
- non-copyable concurrent identity;
- compile-time backend/capability specialization.

Out of scope:

- Task, TaskRef or TaskRecord semantics;
- Worker, Scheduler or Executor types;
- structured-concurrency scopes;
- cancellation;
- parking/wake policy;
- task-state transitions;
- executor selection;
- overflow execution policy;
- reclamation of externally owned pointees;
- policy deciding when batch stealing should be used.

A failed owner insertion reports capacity exhaustion. The consumer decides what
to do next.

## Relationship to the containers-d family model

The proposed family follows the M4 direction already being qualified by
containers-d:

```text
public semantic family
        |
        v
generic mechanics
        |
        v
compile-time specialization / composition
        |
        v
consumer-owned higher-level semantics
```

The work-stealing deque must therefore reuse established package-internal
mechanisms where they are semantically suitable, but it must not force
sequential container abstractions into concurrent code merely for reuse.

In particular, reuse is accepted only when it preserves:

- the concurrent protocol;
- memory-ordering requirements;
- layout requirements;
- zero-cost hot paths;
- clear diagnostics;
- the supported compiler matrix.

A new internal primitive is preferable to a misleading abstraction shared only
by name.

## Working public shape

The current working shape is intentionally provisional:

```d
WorkStealingDeque!(T, Capacity)
```

This is not yet a frozen public name.

Initial direction:

- capacity is compile-time and positive;
- runtime-capacity work stealing is deferred unless independent evidence
  justifies a separate family;
- the type is non-copyable;
- ordinary operations perform no backing allocation;
- full is a normal bounded-container result, not an exceptional condition.

The exact operation names remain open until the API audit, but the semantic
roles are fixed:

```text
owner:
    insert at owner end
    remove from owner end

thief:
    steal one from thief end
    steal a bounded batch from thief end
```

Names must make the owner/thief protocol difficult to misuse without importing
scheduler vocabulary.

## Element contract

The R0.1 consumer evidence uses a trivial non-owning handle representation.
containers-d must define this as a generic supported-T contract rather than
special-case TaskRef.

The first production candidate should deliberately remain narrow.

Required semantic properties for admitted T include:

- fixed-size value transport;
- no queue-owned external resource lifetime;
- no destructor-driven ownership release from a slot;
- no implicit pointee ownership transfer;
- safe bit/value publication according to the qualified D shared/atomic
  protocol;
- reuse of a vacated slot must not retain hidden ownership or reclamation
  obligations.

The exact compile-time predicate is not yet chosen.

It must be derived from compiler-matrix probes rather than from a trait name
alone. Positive and negative consumer compile tests become part of the public
contract.

Do not broaden the supported-T set merely because a more elaborate element can
be made to compile.

## Storage and lifetime

The first family is fixed-capacity and inline unless measurement proves that a
different representation is required.

Element lifetime and slot lifetime are distinct from the lifetime of any
referenced external object.

For non-owning handles:

```text
container owns:
    slot storage
    publication state
    queue position

consumer owns:
    pointee/resource
    reclamation protocol
    lifetime beyond the transported value
```

No reclamation algorithm is implicit in the container.

Any internal raw-memory or atomic bridge must remain a small reviewed
`@trusted` or `@system` boundary with an explicit proof obligation.

## Compile-time composition strategy

The established containers-d strategy remains authoritative.

Preferred escalation order:

1. ordinary templates and traits;
2. `static if` for semantic/backend capability selection;
3. typed template mixins where declaration-local generation is required for
   zero-cost code generation or reusable mechanics;
4. string mixins only if generated syntax itself becomes unavoidable.

The work-stealing family must not introduce a public runtime policy object for
facts known at compile time.

Compiler- or architecture-specific paths are permitted only when:

- caller-visible semantics remain identical;
- capability selection is centralized;
- the portable path remains correct;
- the difference has reproducible evidence;
- removal/requalification conditions are documented.

## Concurrency protocol

The production algorithm must state and test its protocol independently of the
source implementation used as research evidence.

At minimum the specification must define:

- owner-only state transitions;
- thief-visible state;
- publication point for a newly inserted element;
- claim point for a stolen element;
- last-item owner/thief arbitration;
- behavior when the deque is empty;
- behavior when the deque is full;
- slot reuse after successful removal;
- counter/index wrap behavior;
- batch reservation/claim behavior;
- which operations may run concurrently.

`shared` alone is not synchronization. Atomic operations and memory order must
be explicit.

## Batch stealing

Batch stealing is a primitive, not a scheduling policy.

The public shape must specify:

- maximum requested count;
- destination ownership;
- whether the caller supplies destination storage;
- result count;
- all-or-partial behavior;
- ordering of stolen elements;
- behavior during concurrent owner activity;
- no allocation in steady state.

The caller-buffer form is the initial preferred direction because it keeps
allocation and policy outside the container, but it must be qualified before
API freeze.

## Snapshot/introspection

Concurrent snapshots are not automatically part of the public API.

Properties such as an exact concurrent length may require synchronization,
provide only transient information, or encourage incorrect scheduler logic.

Any public observation operation must therefore classify its semantics as one
of:

- exact under an explicit protocol condition;
- owner-local observation;
- approximate/transient;
- unsupported.

No snapshot API is admitted merely because the research implementation had one.

## Counter domain

The retained R0.1 evidence uses a marked-top / finite counter-domain strategy.

Production work must separately decide whether to:

- preserve and document the qualified counter domain; or
- replace it with another representation and requalify correctness and
  performance.

Wrap behavior is a correctness contract, not an implementation afterthought.

## Layout and cache separation

Cache-line separation is an internal performance mechanism unless a caller must
supply or embed storage with a documented alignment requirement.

The production type must not expose a cache-line-size policy parameter merely
to mirror an implementation detail.

Compiler/target-specific layout is acceptable only when the public semantics
and supported embedding contract remain stable.

## Required correctness gates

Before promotion, containers-d must reproduce or strengthen the important R0.1
evidence:

- sequential owner push/pop/steal semantics;
- empty/full transitions;
- deterministic full behavior;
- last-item owner/thief race;
- exact multi-thief accounting;
- no duplicate delivery;
- no lost values;
- counter wrap behavior;
- forced owner/batch overlap;
- concurrent near-capacity operation;
- slot reuse;
- non-copyability;
- supported-T positive compile probes;
- unsupported-T negative compile probes;
- callable `@safe` boundary where claimed;
- `@nogc` and `nothrow` attribute probes where claimed.

Concurrency tests must exercise laws and accounting, not only example
interleavings.

## Compiler and architecture qualification

Initial compatibility target follows the current consumer evidence:

- DMD 2.111 correctness;
- LDC 1.41 correctness and optimized performance;
- native Linux x86_64;
- native Linux AArch64.

The normal containers-d release matrix may impose stronger gates before a
release.

Cross-compilation alone is insufficient evidence for the concurrent memory
ordering protocol.

## Performance qualification

The production family must be measured against:

1. the retained R0.1 candidate;
2. a semantically comparable high-quality C/C++ reference where practical;
3. consumer-neighborhood scheduler workloads before concurrency-d switches.

Measure at least:

- owner-local insert;
- owner-local remove;
- empty steal;
- successful steal;
- owner + one thief;
- owner + multiple thieves;
- batch steal;
- contention;
- distributed producer/stealer behavior;
- recursive/irregular task graphs;
- fine, medium and coarse task granularity.

A local microbenchmark win is insufficient if the consumer-neighborhood
scheduler workload regresses materially.

DMD and LDC may use different internal compile-time-selected mechanisms when
evidence requires it. The public container contract must not change.

## Promotion sequence

The intended work sequence is:

```text
contract draft
    -> API/protocol probes
    -> package-internal research implementation
    -> correctness + memory-order qualification
    -> DMD/LDC codegen/performance qualification
    -> native x86_64 + AArch64 qualification
    -> public API audit
    -> production promotion
    -> concurrency-d consumer acceptance
```

The retained concurrency-d R0.1 implementation remains independent evidence
until the promoted containers-d implementation passes the acceptance gates.

## Immediate next work

The next implementation step is not to expose a public type.

Create a package-internal research prototype that proves:

1. the supported-T predicate on the baseline compilers;
2. fixed-capacity inline storage and non-copyability;
3. the owner/thief state representation;
4. sequential semantics before concurrency;
5. the smallest explicit atomic/memory-order boundary;
6. no runtime policy/configuration state;
7. no dependency on concurrency-d types.

Only then reproduce the concurrent race/accounting corpus.
