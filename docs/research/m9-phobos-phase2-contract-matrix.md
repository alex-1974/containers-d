# Phobos Phase 2 — Ownership and AllocatorList source-review matrix

Date: 2026-10-09. Scope: research only. Builds on Phase 1 results reported by the user: DMD 2.111.0 and LDC 1.41.0 both pass basic `Region!Mallocator`, `BorrowedRegion`, `InSituRegion` unittest probe.

## Confirmed from official Phobos API documentation

- `Region` owns its contiguous backing and releases it on destruction; the container does not itself solve typed destructor, borrow invalidation or escape safety.
- `BorrowedRegion` explicitly does **not** own the supplied backing. The caller is responsible for storage lifetime.
- `InSituRegion` embeds the backing in the struct. Moving the struct may change the underlying addresses; treat address stability across moves as unqualified.
- `AllocatorList` lazily creates child allocators through a factory. It holds a linked list ordered by recent use. An allocation searches existing allocators before growing, so **not unconditionally constant-time**. `deallocateAll()` is only defined when child allocators offer both `owns` and `deallocateAll`. Bookkeeping allocator choice, child-owner moves, and release/retention policy must be qualified before use.

Official references:
https://dlang.org/phobos/std_experimental_allocator_building_blocks_region.html
https://dlang.org/phobos/std_experimental_allocator_building_blocks_allocator_list.html

## New diagnostic package

The standalone XPS package `m9_phobos_phase2.zip` contains
- known passing `region_probe.d`;
- `allocator_contracts.d` introspection of copy/assignment source forms for `Region!Mallocator`, `BorrowedRegion`, `InSituRegion`, **without executing dangerous copies**;
- additional BorrowedRegion `owns`/`deallocateAll`/`empty` tests;
- `run.sh` for DMD/LDC.

**Compilation NOT YET RUN for this Phase 2 package.** Compiler-dependent results must come from XPS. Do not infer safety from compile acceptance or rejection.

## Next required evidence

1. Capture compile results for copy and assignment traits under baseline DMD/LDC.
2. Read matching installed Phobos `region.d` and `allocator_list.d` source for owning copy/move semantics, child-list storage and reset.
3. Build a concrete `AllocatorList` factory only after deciding its child-owner movement and bookkeeping storage. Test stability across list growth, availability, OOM, reset and retention; measure complexity.
4. Continue to defer a public `containers-d` Arena API until independent consumer performance and lifetime gates pass.

No consumer repository modifications; no M9 promotion.

## XPS baseline result (user-run, 2026-10-09)

Compilers: DMD **2.111.0**, LDC **1.41.0**. Both report `1 modules passed unittests` for existing Region probe and allocator-contract diagnostic. Compile-trait observations identical:

| Operation | DMD | LDC |
| --- | --- | --- |
| `Region!Mallocator` copy source form | compiles | compiles |
| `Region!Mallocator` assignment source form | compiles | compiles |
| `BorrowedRegion` copy source form | compiles | compiles |
| `InSituRegion` copy source form | rejected | rejected |

**Safety interpretation:** The acceptance of copy and assignment for an owning Region is a *critical ownership red flag*, not a proven runtime double-free. The official Region documentation says it releases backing on destruction. Validate the exact installed Phobos postblit/constructor/assignment code before any runtime copy probe, and **never execute actual copied owning Region values** without a guarded instrumentation scheme. D language construction/NRVO versus assignment paths also differ. BorrowedRegion copy may be reasonable but does not create independent backing; reset and backing lifetime remain caller-managed. InSituRegion copy rejection is specific to the tested source form, not proof of complete address-stable ownership.

Official API references:
- https://dlang.org/library/std/experimental/allocator/building_blocks/region/region.html
- https://dlang.org/library/std/experimental/allocator.html

### Updated decision

Block any promotion of `Region!Mallocator` as a uniquely-owned container until source-level copying/destruction is audited. Prefer a non-owning region with an externally controlled owner for next research, with a **strict reset/borrow boundary**; no public `@safe` claims. Next collect installed Phobos source snippets of constructors, destructor and copy/assignment declarations from both toolchains and qualify `AllocatorList` ownership before executing it. No production API or consumer changes.
