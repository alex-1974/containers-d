# Work-stealing deque public API qualification

Status: qualified production API; frozen for the first public surface  
Tracking: issue #38

## Public module and type

Candidate public module:

```d
import containers.work_stealing_deque : WorkStealingDeque;
```

Candidate package-root export:

```d
import containers : WorkStealingDeque;
```

Candidate type:

```d
WorkStealingDeque!(T, Capacity)
```

`Capacity` is the semantic element count. The research-only `LogSize` shape is
not promoted.

Current capacity contract:

- 64-bit target;
- `Capacity >= 2`;
- power of two;
- `Capacity <= 2^61`;
- fixed at compile time;
- no runtime-capacity variant in the first family.

Runtime capacity is deferred rather than hidden behind a policy parameter.

## Initialization and identity

`.init` is a valid empty deque.

The deque is a synchronization object with identity:

- copy construction is disabled;
- assignment is disabled;
- move construction / relocation as a value is disabled;
- destruction performs no element finalization because admitted T values do
  not own destructor-driven lifetime.

The object must therefore be established at its final address before owner/
thief access begins.

## Element contract

The first production family admits only values that satisfy all of:

- atomic shared load/store through `core.atomic` compiles;
- no destructor-owned element lifetime;
- no elaborate copy/postblit contract;
- no implicit pointee ownership;
- any referenced object has externally managed lifetime;
- shared-compatible indirections only.

Examples intended to qualify:

- integral scalar handles;
- small trivial value structs;
- shared-pointer handle structs such as `shared(TaskRecord)*` wrappers.

Examples intentionally rejected:

- ordinary unshared pointers;
- class references;
- destructor-owning values;
- postblit/elaborate-copy values;
- domain objects whose ownership would be transferred by queueing.

The internal research predicate is not itself promised as public API. The public
contract is expressed by template diagnostics and Ddoc.

## Operations

Candidate first surface:

```d
enum size_t capacity;

bool tryPush(T value);
WorkStealingTakeResult!T pop();
WorkStealingTakeResult!T steal();
size_t stealBatch(scope T[] output);
```

Semantic roles:

- `tryPush`: owner-only insertion; false means full;
- `pop`: owner-only LIFO removal; `found == false` means no value won by owner;
- `steal`: thief-safe FIFO removal; `found == false` means no value obtained;
- `stealBatch`: thief-safe FIFO-prefix removal into caller-owned output;
  returns the number written.

`pop` is not a precondition operation: even an apparently non-empty deque can
lose the last-item race to a thief. The result carrier therefore remains
explicit.

## Result carrier

Candidate carrier:

```d
struct WorkStealingTakeResult(T)
{
    T value;
    bool found;
}
```

`T.init` is never used as an empty sentinel.

The carrier is preferred over an `out T` API because absence is represented
explicitly without requiring callers to predeclare mutable storage and without
making output-initialization behavior part of the operation contract.

## Batch contract

`stealBatch(scope T[] output)`:

- `output` is caller-owned;
- no allocation occurs;
- zero-length output returns zero;
- values are written in thief/FIFO order;
- at most `output.length` values are written;
- return value is exactly the initialized prefix length;
- the remainder of `output` is untouched;
- the operation does not choose whether batch stealing is desirable.

The consumer owns batch-size policy.

## Snapshot decision

The first public API exposes **no `size`, `empty`, `full`, or approximate
snapshot operation**.

Reason:

- concurrent observations are immediately stale;
- owner/thief algorithms must not use a snapshot as an admission precondition;
- `tryPush`, `pop`, `steal`, and `stealBatch` already encode the actionable
  outcomes;
- omitting snapshots keeps the first contract narrow and prevents accidental
  synchronization assumptions.

Diagnostic snapshots may remain research-only. A later observation API would
require an explicit exact/approximate semantic contract.

## Protocol safety

Language safety and concurrency protocol are distinct.

Qualified callable attributes:

```text
@safe @nogc nothrow
```

Protocol precondition:

```text
exactly one owner thread may call tryPush/pop
zero or more thief threads may call steal/stealBatch
```

`@safe` does not enforce the one-owner protocol. Violating it is a concurrency
contract violation even though the calls are language-memory-safe.

## Memory ordering

The selected implementation preserves the qualified P08e marked-top protocol:

- release publication of owner bottom after slot store;
- acquire observations by thieves;
- sequentially-consistent arbitration/barrier at the last-item and batch
  reservation boundaries;
- marked top excludes ordinary thieves and causes owner pop to restore/retry;
- one narrow trusted SC-barrier helper; normal public operations remain
  `@safe`.

The public API documents the protocol guarantee, not individual atomic
instructions as a caller-configurable policy.

## Counter domain

The implementation uses a 63-bit modular logical sequence domain plus one
batch-busy marker bit.

Correctness is qualified across counter wrap under the bounded occupancy
invariant. Callers do not manage counters directly.

The power-of-two capacity and upper capacity bound are public compile-time
constraints; the bit encoding itself remains implementation detail.

## Cache layout

The qualified implementation separates top-side and owner-bottom state by
64 bytes and places the element array after the second 64-byte state region.

This is an internal performance layout, not a public aggregate alignment or
embedding guarantee. Future compiler/architecture-specific layout changes may
be selected privately if semantics and performance are requalified.

## Deferred from the first API

- runtime capacity;
- resize/growth;
- allocator selection;
- scheduler overflow policy;
- parking/wake integration;
- reclamation/epoch ownership;
- task-specific types;
- public memory-order selection;
- public cache-line/layout policy;
- size/empty/full snapshots;
- generalized MPSC/MPMC semantics.

## API freeze result

The first public surface is frozen for production promotion.

Qualification completed:

1. non-copy, non-assignment, non-move and pass-by-value forms are rejected
   on the controlled DMD/LDC matrix;
2. destructor-owning, postblit and unshared-pointer element forms are
   rejected;
3. native x86_64 and AArch64 concurrent correctness is qualified;
4. pinned-P08e DMD/LDC retired-instruction parity is exact;
5. native AArch64 normalized instruction streams are exact;
6. balanced four-physical-core AArch64 contention shows no material
   regression;
7. package-root and exported-archive consumers compile and run;
8. Ddoc and release builds pass;
9. the six controlled compiler versions and Linux/Windows/macOS promotion
   matrix pass.

Future API additions require their own semantic and performance evidence.
The first surface intentionally remains narrow.
