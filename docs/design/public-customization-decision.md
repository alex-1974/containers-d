# M4.6 public customization decision

Status: accepted design decision  
Tracking: issue #52  
Parent architecture: issue #23

## Decision

containers-d does not expose an advanced public customization or policy
framework after M4.

The public API remains a set of concrete semantic container families. Internal
implementation may use D compile-time mechanisms aggressively where evidence
shows they improve reuse, correctness or generated code.

## Evidence

M4 established four relevant facts.

1. M4.2 showed that common element-lifetime and raw-storage mechanics can be
   shared internally through templates and typed mixins without making them a
   public compatibility surface.
2. M4.3 showed that StaticVector benefits from compile-time-selected internal
   representations, while callers need only the semantic vector contract.
3. M4.4 showed that StaticRingBuffer and RingBuffer can share a narrow
   sequencing mixin with exact code-generation neutrality while remaining
   distinct public ownership/storage families.
4. M4.5 showed that real consumers divide by semantics: caller-owned numerical
   workspaces, synchronized bounded mailboxes, reusable scratch, arenas,
   pools, and domain-specific retained resources are not arbitrary policy
   combinations of one universal container.

## Public model

The intended model is:

```text
semantic public family
    |
    +-- narrow documented contract
    +-- family-specific ownership/lifetime/failure semantics
    |
    v
package-internal implementation
    |
    +-- ordinary templates / traits
    +-- static if capability selection
    +-- typed template mixins where qualified
    +-- compiler/architecture specialization where measured
```

Examples of public semantic families include:

- StaticVector;
- StaticRingBuffer;
- RingBuffer;
- future BlockingQueue;
- future ScratchBuffer / Arena / BufferPool where separately justified;
- future WorkStealingDeque and other explicit concurrent families.

## Not public API

The following remain implementation details unless later consumer evidence
changes the decision:

- element-lifetime mixins;
- raw-slot/storage contracts;
- inline-storage mixins;
- ring-sequencing mixins;
- compiler/backend capability selectors;
- cache-line/layout implementation selectors;
- allocator or synchronization policies that would alter family semantics.

## Rejected design

M4 explicitly rejects a public framework of the form:

```d
Container!(
    StoragePolicy,
    GrowthPolicy,
    OwnershipPolicy,
    ConcurrencyPolicy,
    OverflowPolicy,
    BackendPolicy)
```

Such a type would mix semantically different families, enlarge the
compatibility surface, complicate diagnostics and documentation, and invite
invalid or unqualified policy combinations.

## Consumer adaptation

Consumers may adapt containers-d in three ways:

1. use a public family directly where semantics match;
2. wrap/compose a public family under domain vocabulary and invariants;
3. keep a domain-specific structure and reuse no generic container when that is
   the clearer or faster contract.

Caller-owned slices/workspaces remain a valid first-class API and do not need
an owning containers-d type merely for uniformity.

## Reconsideration gate

Public advanced customization may be reconsidered only when all of the
following are true:

- at least two materially different real consumers need the same semantic
  family;
- they require different backends/storage mechanisms that cannot be selected
  privately without changing source-visible behavior;
- wrappers would materially weaken performance, safety or API clarity;
- the proposed customization has bounded legal combinations and useful
  diagnostics;
- template/build cost and binary-size impact are measured;
- DMD/LDC and relevant architecture performance is qualified.

Until then, implementation variation is private and automatically selected.

## M4 exit

M4 exits with:

- a concrete family model;
- qualified internal compile-time composition;
- StaticVector promoted as a new public family;
- zero-cost shared ring sequencing;
- real-consumer adaptation evidence;
- no universal public policy framework.

Future work proceeds family by family under independent correctness, safety,
ownership and performance gates.
