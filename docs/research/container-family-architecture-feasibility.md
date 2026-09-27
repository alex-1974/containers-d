# Container family architecture feasibility study

Status: research  
Parent: issue #23  
Date: 2026-09-27

## 1. Question

Can containers-d be designed as a small family of generic high-performance
buffer/container algorithms whose ordinary public forms are immediately useful,
while advanced consumers may adapt selected mechanisms at compile time for their
own workloads without paying a runtime abstraction cost?

The target is not a universal policy container.

The target is:

```text
small set of algorithmic families
        +
stable default public types
        +
narrow compile-time adaptation points
        +
consumer/domain wrappers
```

## 2. Feasibility conclusion

Yes, the model is technically feasible in D.

D already provides the mechanisms required for this architecture:

- type/value/alias template parameters;
- template constraints;
- `static if`;
- `__traits(compiles, ...)` and `std.traits`;
- CTFE;
- compiler/platform `version` identifiers;
- `__VERSION__` / `__VENDOR__`;
- template mixins where declaration injection is genuinely useful.

The existing containers-d implementation already proves a narrow version of
the model:

```d
RuntimeStorageOwner!(
    T,
    Backend = AlignedStorageBackend
)
```

The runtime ring buffer itself exposes only the qualified default backend, while
its storage owner is already compiled against an interchangeable backend type.

The main feasibility risk is therefore not whether D can express the design.
It can.

The real risks are:

- exposing too many orthogonal policy parameters;
- making safety depend on weakly specified consumer backends;
- template-instantiation/code-size growth;
- compiler-time growth;
- poor diagnostics;
- accidentally changing semantic contracts through mechanical customization;
- losing performance through abstraction that is expected, but not proven, to
  inline away.

The architecture below is designed to control those risks.

## 3. The model: family tree plus orthogonal properties

A pure inheritance tree is insufficient.

For example, MPSC is not inherently a subtype of RingBuffer, and an Arena is
both a storage mechanism and a lifetime model.

The proposed model therefore has two dimensions:

1. **algorithmic family** — the stable data-structure invariant;
2. **orthogonal mechanism** — storage/lifetime/concurrency details that may vary.

```text
                         container algorithms
                                  |
          +-----------------------+-----------------------+
          |                       |                       |
    contiguous sequence      circular sequence      segmented sequence
          |                       |                       |
    StaticVector             StaticRingBuffer         SegmentedBuffer
    Vector                   RingBuffer               SegmentedQueue
    SmallVector                  |                    ChunkedVector
    ScratchBuffer                |
                                 +-- Queue facade
                                 +-- BlockingQueue
                                 +-- SPSC/MPSC research
          
          +-----------------------+-----------------------+
          |                       |                       |
     monotonic memory          reusable memory       ordered/indexed
          |                       |                       |
        Arena                 BufferPool                 Heap
     ScratchArena             BlockPool             PriorityQueue
      FrameArena             SizeClassPool
```

Consumer/domain types sit above or beside these families:

```text
geo-d ExpansionBuffer
    <- StaticVector family

osm-d decompression blocks
    <- UniqueBuffer / BufferPool family

raster-d StageMailbox
    <- bounded FIFO + blocking synchronization

DCanvas EventQueue
    <- FIFO family + MPSC + cancellation semantics

DCanvas FrameArena
    <- Arena family + frame reset lifetime

imagery-d decoded cache
    <- buffer ownership primitives + imagery-specific cache policy
```

The consumer leaf may wrap, compose, or specialize a generic primitive. It does
not require every consumer-specific semantic to become a containers-d policy.

## 4. Separate the invariant from the mechanism

For every family we must explicitly identify what cannot change without becoming
a different semantic type.

### RingBuffer invariant

Invariant:

- bounded capacity;
- FIFO logical ordering;
- circular physical reuse;
- no overwrite on ordinary insertion;
- O(1) front/back/index/push/pop;
- exactly `length` live T objects.

Mechanisms that may vary without changing that invariant:

- inline versus owned backing;
- allocation backend for owned backing;
- alignment above T.alignof when required;
- compiler-qualified wraparound implementation;
- instrumentation around allocation.

Mechanisms that SHOULD create another family/type:

- overwrite-on-full;
- automatic growth;
- SPSC/MPSC/MPMC synchronization;
- cancel-by-ID;
- priority ordering.

### Linear vector invariant

Invariant:

- one logically contiguous sequence;
- random access;
- append/pop at the back;
- initialized prefix [0, length);
- capacity at least length.

Mechanisms that may vary:

- inline versus heap storage;
- allocation backend;
- growth strategy;
- additional alignment;
- retention/shrink strategy.

Semantic variants:

- fixed capacity -> StaticVector;
- growable -> Vector;
- inline-first then grow -> SmallVector;
- reusable workspace semantics -> ScratchBuffer.

### Arena invariant

Invariant:

- allocations proceed monotonically within a generation;
- individual allocation release is absent or deliberately restricted;
- reset/release ends the generation.

Mechanisms that may vary:

- inline first block;
- upstream block provider;
- block growth;
- alignment;
- optional destructor tracking.

Thread sharing is not a casual policy; a concurrent arena should require a
separate contract.

## 5. Proposed implementation layering

The strongest design is not one giant `BasicContainer!(Policies...)`.

Use several narrow layers.

### Layer 0 — element lifetime machinery

Internal and not consumer-configurable.

Responsibilities:

- construct into raw slot;
- move/copy according to D language semantics;
- destroy live T;
- clear vacated pointer-bearing storage where required;
- classify `T` using compiler/library traits;
- centralize audited `@trusted` placement/lifetime bridges.

Candidate internal module:

```text
containers.internal.element_lifetime
```

This logic is common to StaticVector, Vector, SmallVector, RingBuffer and other
slot-owning families.

It should not be customizable because incorrect substitution can violate object
lifetime and memory safety.

### Layer 1 — raw storage owners/providers

Own or expose raw slots but do not decide which slots contain live T objects.

Current precedent:

```text
RuntimeStorageOwner!T
    |
    +-- aligned byte block
    +-- capacity
    +-- slotPointer
    +-- slotSlice
    +-- GC range registration
    +-- release
```

Candidate future storage primitives:

```text
InlineRawStorage!(T, N)
UniqueRawStorage!(T, Backend)
ExternalRawStorage!T          [only if a real consumer proves it]
SegmentBlockStorage!(T, ...)
```

Storage contracts should be structural compile-time contracts.

Required capabilities are checked through template constraints/traits.
Optional capabilities should be detected rather than represented by runtime
flags.

### Layer 2 — family state and algorithms

Keep algorithmic state small and explicit.

Examples:

```d
struct RingState
{
    size_t head;
    size_t length;
}

struct LinearState
{
    size_t length;
}
```

Family algorithms operate on the state plus a storage satisfying the required
compile-time contract.

Conceptually:

```text
ring physical-index algorithm
ring append algorithm
ring pop algorithm

linear append algorithm
linear relocation algorithm
linear reserve algorithm
```

The special-member semantics of public owners need not be forced into one
generic mega-core. Public containers may retain their precise copy/move/destruct
contracts while sharing the ordinary hot-path algorithms.

This is important because StaticRingBuffer and RingBuffer already differ
materially in whole-owner copy/move semantics.

### Layer 3 — public default containers

The ordinary API remains simple:

```d
StaticVector!(T, N)
Vector!T
SmallVector!(T, N)

StaticRingBuffer!(T, N)
RingBuffer!T

ScratchBuffer!T
Arena
```

Defaults are not second-class convenience aliases. They are the principal,
performance-qualified product.

A user should never need a customization profile merely to get good behaviour.

### Layer 4 — advanced customization surface

Only proven mechanical extension points are exposed.

Possible future module:

```d
import containers.custom;
```

Candidate forms:

```d
CustomRingBuffer!(T, StorageBackend)
CustomVector!(T, VectorProfile)
CustomScratchBuffer!(T, StorageBackend)
```

The exact spelling is deliberately not decided by this research.

Important rule:

A customization point becomes public only when:
- at least two real consumers require materially different mechanisms;
- the semantic container invariant remains unchanged;
- the alternative can be validated independently;
- default performance is not penalized;
- the safety boundary can be specified.

## 6. Why structural compile-time contracts fit D

D does not require an OO interface for a compile-time concept.

A storage contract can be checked with ordinary expressions:

```d
enum bool isRawSlotStorage(S, T) =
    __traits(compiles, {
        S storage;
        size_t n = storage.capacity;
        T* slot = storage.slotPointer(0);
        T[] span = storage.slotSlice(0, 0);
    });
```

The real implementation would use stronger probes and explicit documentation.

This is analogous to D range concepts:
an input range is recognized from operations such as `empty`, `front` and
`popFront`, not by inheriting an interface.

It is also analogous to Phobos allocator building blocks, where required and
optional allocator capabilities are identified statically from the operations
the allocator implements.

This gives:

- static dispatch;
- no vtable;
- no interface pointer in the container;
- no runtime policy branch;
- compile-time rejection of mechanically incompatible providers.

Semantic obligations that cannot be mechanically proved must still be
documented and tested.

## 7. Customization mechanisms: what to use

### Preferred: ordinary templates + static if

Use for:

- storage/backend types;
- compile-time capacity;
- element-trait specialization;
- optional backend capabilities;
- compiler-qualified implementation selection.

Example shape:

```d
static if (hasIndirections!T)
{
    // GC-visible storage handling
}

static if (backendSupportsAlignedAllocate!Backend)
{
    ...
}
```

### Preferred: traits / __traits(compiles)

Use to establish structural concepts and derive capabilities.

Examples:

- `isRawStorageBackend`;
- `canReallocateInPlace`;
- `hasBulkReset`;
- `hasStaticCapacity`;
- `isNothrowStorage`.

Avoid requiring consumers to duplicate explicit capability flags when the
capability is mechanically detectable.

### Preferred: CTFE

Use for:

- checked static byte sizing;
- power-of-two/capacity classification;
- derived alignment;
- fixed workspace sizes;
- compile-time lookup/strategy selection where qualified.

### Restricted: compiler/platform specialization

D exposes compiler/platform version identifiers and compiler version tokens.

Use them only internally for measured differences.

Example:

```text
same public container
      |
      +-- DMD-qualified implementation
      +-- LDC-qualified implementation
```

The consumer should not choose the compiler strategy.

### Restricted: template mixins

Template mixins can eliminate repeated declarations, but they are evaluated in
the scope into which they are mixed.

Use them only where this behaviour is explicitly useful.

Good possible use:
- small, audited method families forwarding a stable container API.

Poor use:
- hidden ownership/lifetime logic;
- large algorithm implementations depending on host field names;
- public customization by injecting implementation internals.

### Avoid by default: string mixins

String-generated container code would make diagnostics, refactoring and review
harder.

Use only if a future proven code-generation case cannot be expressed cleanly
with typed templates/CTFE.

## 8. Public adaptation should have levels

### Level 1 — default consumer

```d
auto queue = RingBuffer!Job(1024);
StaticVector!(Point2!double, 16) points;
Vector!Node nodes;
```

No policy knowledge.

### Level 2 — explicit standard variants

```d
SmallVector!(Token, 16)
ScratchBuffer!Pixel
BlockingQueue!Task
```

The type communicates the semantic difference.

### Level 3 — advanced mechanical customization

Only for consumers such as libraries, engines, embedded systems or specialized
pipelines.

Conceptually:

```d
alias WorkerBuffer =
    CustomUniqueBuffer!(
        ubyte,
        WorkerPoolBackend
    );
```

or:

```d
alias RenderVertices =
    CustomVector!(
        Vertex,
        RenderStorageProfile
    );
```

No runtime policy object is required when the mechanism is fully known at
compile time.

### Level 4 — domain wrapper

```text
containers-d StaticVector
       |
       v
geo-d ExpansionBuffer

containers-d bounded FIFO
       |
       v
raster-d StageMailbox

containers-d Arena
       |
       v
DCanvas FrameArena
```

Domain semantics remain owned by the consumer.

## 9. Family tree with current workspace leaves

```text
RAW STORAGE / LIFETIME FOUNDATION
|
+-- inline raw slots
|   |
|   +-- CONTIGUOUS FIXED FAMILY
|   |   +-- StaticVector
|   |       +-- geo-d ExpansionBuffer candidate
|   |       +-- geo3-d ExpansionBuffer candidate
|   |       +-- DCanvas short temporary sequences
|   |
|   +-- CIRCULAR FIXED FAMILY
|       +-- StaticRingBuffer
|
+-- unique owned raw slots
|   |
|   +-- CONTIGUOUS OWNED FAMILY
|   |   +-- UniqueBuffer
|   |   +-- Vector
|   |   +-- ScratchBuffer
|   |       +-- geo-d simplification/topology workspace owner
|   |       +-- osm-d StringTable/decompression workspace owner
|   |       +-- DCanvas raster/render scratch
|   |
|   +-- INLINE-FIRST CONTIGUOUS FAMILY
|   |   +-- SmallVector
|   |       +-- DCanvas wrap/layout/listener candidates
|   |
|   +-- CIRCULAR OWNED FAMILY
|       +-- RingBuffer
|           +-- Queue facade
|           +-- BlockingQueue
|               +-- raster-d StageMailbox candidate
|               +-- DCanvas RunnableQueue candidate
|
+-- segmented/chunked storage
|   |
|   +-- SegmentedBuffer
|   +-- SegmentedQueue
|       +-- DCanvas unbounded worker/send queue candidate
|
+-- monotonic block storage
|   |
|   +-- Arena
|       +-- ScratchArena
|       +-- DCanvas FrameArena
|       +-- geo-d polygon-union workspace candidate
|       +-- raster/imagery request-workspace candidate
|
+-- recyclable storage
    |
    +-- BufferPool
        +-- osm-d per-worker decompression blocks
        +-- DCanvas receive blocks
        +-- imagery decoded/source blocks
```

Concurrency overlays the appropriate families rather than sitting inside every
storage type:

```text
single-threaded / externally synchronized
blocking mutex+condition
SPSC
MPSC
MPMC
```

Only some combinations are meaningful.

## 10. Feasibility per family

| Family | Shared algorithm potential | Useful adaptation | Risk |
|---|---:|---|---|
| StaticVector | very high | mostly T/N, possibly alignment | low |
| Vector | high | backend, growth, alignment | medium |
| SmallVector | high | inline N, backend/growth after spill | medium |
| RingBuffer | already proven high | owned backend/alignment | low-medium |
| BlockingQueue | high over bounded FIFO | wait/sync semantics mostly fixed | medium |
| SegmentedQueue | high | segment size/backend | medium |
| ScratchBuffer | high | backend/retention | low-medium |
| Arena | high | block provider/growth/destructor tracking | medium |
| BufferPool | medium | size classes/backend/thread model | high |
| SPSC/MPSC | family-specific | capacity/layout/cache-line choices | high |

The high-risk families should not be forced through a generic policy framework
designed for the low-risk families.

## 11. Important safety limitation

Compile-time structural checking proves that methods exist and have usable
types/attributes.

It cannot prove semantic allocator/storage invariants such as:

- returned memory is genuinely unique;
- alignment claims are true;
- two live allocations do not overlap;
- a backend does not free storage prematurely;
- deallocation matches acquisition;
- a pool does not hand the same block to two owners.

Therefore an advanced consumer-supplied backend is itself part of the trusted
memory-safety boundary.

containers-d can:

- constrain the callable surface;
- minimize its own `@trusted` code;
- test supplied standard backends;
- document backend obligations.

It cannot turn a semantically invalid custom allocator into safe storage merely
through templates.

This is a strong reason to expose a small backend contract rather than arbitrary
hooks throughout element lifetime machinery.

## 12. Performance model

Compile-time specialization can remove runtime dispatch, but zero overhead must
still be measured.

For every customizable family test:

### Runtime cost

Compare the default facade against a direct/reference implementation for:

- retired instructions;
- branches;
- loads/stores;
- throughput/latency;
- allocations;
- generated code where useful.

### Compile-time cost

Track:

- build time;
- number of template instantiations;
- binary/text size;
- duplicate instantiations across representative consumers.

DMD provides template-instantiation diagnostics; these should become part of an
advanced-customization qualification harness if the design is promoted.

### Code-size control

Avoid combinatorial policy matrices.

Support a few coherent profiles/backends instead of allowing arbitrary
independent switches for every implementation detail.

## 13. Proposed customization taxonomy

### Automatically selected by containers-d

Never ask the consumer to select these:

- modulo vs branch vs mask;
- compiler-specific indexing shape;
- memcpy vs element operation;
- GC slot clearing;
- element destructor path;
- language move path;
- SIMD/internal codegen variant;
- prefetch/unroll thresholds.

These are implementation optimizations.

### Potentially consumer-selectable after evidence

These can represent real environmental constraints:

- storage allocation backend;
- explicit extra alignment;
- vector growth profile;
- scratch retention policy;
- segment/block size;
- upstream arena provider.

### Separate semantic type/family

Do not make these boolean policies:

- bounded vs growable;
- reject-full vs overwrite-full;
- single-threaded vs MPSC;
- FIFO vs priority;
- ordinary queue vs cancelable event queue;
- persistent sequence vs generation-reset arena;
- contiguous vs segmented.

## 14. Concrete first proof: StaticVector

StaticVector is the best first architecture experiment because:

- geo-d and geo3-d already contain nearly identical ExpansionBuffer shapes;
- no heap allocator is involved;
- the element-lifetime machinery is still non-trivial;
- the fixed layout makes generated-code comparison straightforward.

Prototype research should compare:

```text
A. current geo-d ExpansionBuffer
B. direct standalone StaticVector
C. StaticVector using shared internal lifetime/linear core
D. geo-d ExpansionBuffer wrapper over StaticVector
```

Acceptance:

- same semantics;
- same or better safety;
- no allocation;
- no material DMD/LDC runtime regression;
- acceptable compile-time/code-size cost.

This proves whether family factoring itself is zero-cost before adding allocator
customization.

## 15. Second proof: runtime storage customization

The second experiment should use the already existing backend seam.

Compare:

```text
RingBuffer!T current default
RingBuffer-like prototype over same RuntimeStorageOwner
same family core over a counting backend
same family core over a deliberately over-aligned backend
```

The purpose is not to redesign RingBuffer immediately.

It is to prove:

- shared family algorithms compile away cleanly;
- an alternate backend does not add runtime indirection;
- default code remains unchanged or equivalent;
- backend capability constraints produce understandable diagnostics.

## 16. Third proof: real consumer specialization

Use one actual workspace consumer.

Strong candidates:

### raster-d StageMailbox

Replace only the research mailbox's hand-written slot/head/count FIFO storage
with a containers-d bounded FIFO primitive while retaining its own
Mutex/Condition/close semantics.

This tests composition.

### geo-d ExpansionBuffer

Wrap StaticVector without changing exact arithmetic callers.

This tests domain wrapping.

### osm-d decompression workspace

Provide a reusable owning/pool-backed buffer to the existing caller-slice API.

This tests storage substitution without changing algorithm API.

Success across these three consumers would demonstrate three different
adaptation modes:

```text
composition
domain wrapper
storage provider
```

## 17. Rejected architecture: universal policy container

Do not build:

```d
Container!(
    T,
    LayoutPolicy,
    StoragePolicy,
    GrowthPolicy,
    OverflowPolicy,
    ThreadPolicy,
    BoundsPolicy,
    LifetimePolicy,
    AlignmentPolicy,
    FailurePolicy,
    DebugPolicy,
    ...
)
```

Problems:

- combinatorial testing;
- template/code-size explosion;
- poor diagnostics;
- unclear semantic identity;
- invalid combinations;
- consumers must understand internals;
- optimization choices become API promises.

The family architecture gains most of D's compile-time benefit without this
cost.

## 18. Promotion criteria

The family architecture is accepted only if the experiments show:

1. shared family kernels do not materially regress default hot paths;
2. default public types remain simple;
3. advanced customization introduces no runtime dispatch by construction;
4. the trusted safety boundary stays narrow;
5. semantic differences remain distinct types;
6. consumer backends can be structurally validated;
7. compiler diagnostics are usable;
8. template-instantiation/build-size costs remain acceptable;
9. at least three real workspace consumers demonstrate different adaptation
   modes;
10. the existing v0.1 RingBuffer contracts need not be broken merely to adopt
    the architecture internally.

## 19. Current verdict

**Feasible and promising, but it should be proven incrementally rather than
declared as a universal framework up front.**

The recommended sequence is:

```text
1. shared element-lifetime primitives
2. StaticVector family-core experiment
3. ring-family factoring experiment without public API change
4. geo-d wrapper proof
5. raster-d composition proof
6. osm-d storage/pool proof
7. only then decide the public advanced-customization API
```

This sequence preserves the current evidence-first engineering rule: the family
model is adopted only where DMD/LDC correctness, safety, compile-time cost and
runtime performance demonstrate that the abstraction is genuinely zero-cost or
worth its measurable cost.
