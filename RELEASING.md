# Releasing containers-d

This document describes the current release process for `containers-d`.

The active stabilization target is `v0.2.0`. The release adds the qualified
`StaticVector`, `ScratchBuffer`, `WorkStealingDeque`, and `BlockingQueue`
families to the ring-buffer API released in v0.1.x.

## 1. Feature freeze

The v0.2.0 feature set was frozen at:

```text
d385359c5ce4b5fe8ca16a8293860860d3ca5680
```

The stabilization branch starts from exactly that commit:

```text
release/0.2
```

No new container family enters the v0.2.0 release line after this point.
Bug fixes, regression tests, benchmark work, API corrections found by the
release audit, comments, documentation, CI, and packaging work remain allowed.

Create the immutable annotated feature-freeze checkpoint from a clean local
checkout:

```bash
git fetch origin --prune
git switch release/0.2
git pull --ff-only origin release/0.2

FEATURE_FREEZE=d385359c5ce4b5fe8ca16a8293860860d3ca5680

git tag -a freeze/feature-0.2.0 "$FEATURE_FREEZE" \
  -m "containers-d v0.2.0 feature freeze"
git show --no-patch --decorate freeze/feature-0.2.0
test "$(git rev-parse freeze/feature-0.2.0^{commit})" = "$FEATURE_FREEZE"

git push origin freeze/feature-0.2.0
```

The checkpoint is engineering evidence. It is immutable, is not a package
version, and must not create a GitHub Release.

## 2. Stabilization work

Track the release through issue #66.

The stabilization pass includes:

- benchmark and performance qualification;
- public API and export audit;
- source comments and Ddoc hardening;
- documented executable examples;
- DDox rendered-site qualification;
- CHANGELOG and release-note reconciliation;
- compiler and portability gates;
- package/archive boundary checks.

Issues #8 and #10 remain independent research unless the API audit shows that
one is a release blocker.

## 3. Documentation standard

The source Ddoc attached to public declarations is the authoritative API
contract.

Each public container family explains:

- what problem it solves;
- what it can do;
- what it deliberately does not do;
- storage, ownership, allocation, lifetime, failure, and concurrency semantics
  where they are caller-visible.

Each meaningful family has a documented `unittest` that is compiled and run
with the normal test suite and rendered by DDox. Examples should show normal
use, not merely prove syntax.

Public functions, methods, properties, result carriers, and templates document
their caller-visible inputs and outputs, preconditions, result/failure
semantics, mutation and invalidation, allocation, concurrency, and complexity
where applicable.

Source comments explain non-obvious engineering decisions: invariants,
lifetime, GC visibility, alignment, memory ordering, `@trusted` proof
obligations, toolchain workarounds, and performance-sensitive specialization.
Comments explain why unusual code exists instead of paraphrasing the syntax.

Write plainly. Prefer short concrete sentences, active verbs, and necessary
technical terms. Remove clutter. This follows the practical clarity and
economy principles associated with William Zinsser's *On Writing Well*.

## 4. API freeze

Do not create the API-freeze checkpoint until the baseline performance work and
public API audit are complete.

The API freeze covers public names and exports, module/import surface,
signatures and parameter order, template constraints, ownership and lifetime,
failure semantics, documented `.init` behavior, attributes, and other
source-compatibility promises.

From the exact qualified release-line commit:

```bash
API_FREEZE="$(git rev-parse HEAD)"

git tag -a freeze/api-0.2.0 "$API_FREEZE" \
  -m "containers-d v0.2.0 API freeze"
git show --no-patch --decorate freeze/api-0.2.0
test "$(git rev-parse freeze/api-0.2.0^{commit})" = "$API_FREEZE"

git push origin freeze/api-0.2.0
```

If a release blocker requires a public API change later, do not move this tag.
Reopen the API freeze, correct and re-audit the API, then create a new immutable
checkpoint such as `freeze/api-0.2.0-r2`.

## 5. Required qualification

Before promotion to `main`, require:

- DMD 2.111.0, 2.112.1, and 2.113.0;
- LDC 1.41.0, 1.42.0, and 1.43.0;
- normal and DIP1000 unit tests;
- external consumer coverage for the complete public family set;
- WorkStealingDeque concurrent correctness;
- BlockingQueue public consumer coverage;
- StaticVector lifecycle/adversarial/GC qualification;
- runtime and static-ring GC/alignment qualification;
- negative compile-contract tests;
- release build;
- Ddoc source build and DDox rendered API build;
- archive boundary audit and archive-only consumer smoke;
- Linux ARM64, Windows x64, macOS Intel, and macOS ARM64 portability jobs.

The Release Gate runs on pushes to `release/**` and on release PRs to
`main`.

## 6. Changelog and release identity

Before the release candidate is promoted, replace the Unreleased heading with:

```text
## [0.2.0] - YYYY-MM-DD
```

The changelog must describe the actual frozen public API and must agree with the
README, source Ddoc, DDox output, and release notes.

Record the exact qualified release commit:

```bash
RELEASE_COMMIT="$(git rev-parse HEAD)"
printf '%s\n' "$RELEASE_COMMIT"
```

## 7. Promote to main

Open the release PR from `release/0.2` to `main`. Merge only when every
required check is green on the exact PR head.

The merge or promoted commit on `main` must pass the Release Gate again. The
release tag is created only from that same qualified `main` state.

## 8. Final local verification

From a clean checkout of the qualified release commit:

```bash
dub describe
dub test --compiler=dmd --force
dub build --build=release --compiler=dmd --force
dub build -b ddox --compiler=dmd --force

tmp="$(mktemp -d)"
git archive HEAD | tar -xf - -C "$tmp"
(cd "$tmp" && dub test --compiler=dmd --force)
```

The exported package contains consumer source and package metadata, not
repository tests, benchmarks, evidence, or CI configuration.

## 9. Create the release tag

Release tags must be annotated and should be signed.

```bash
git switch main
git pull --ff-only origin main

RELEASE_COMMIT="$(git rev-parse HEAD)"

git tag -s v0.2.0 "$RELEASE_COMMIT" -m "containers-d v0.2.0"
git show --no-patch --decorate v0.2.0
test "$(git rev-parse v0.2.0^{commit})" = "$RELEASE_COMMIT"

git push origin v0.2.0
```

If signing is temporarily unavailable, use an annotated tag with `git tag -a`
and record the reason. Do not create a lightweight release tag.

Publishing the tag triggers `.github/workflows/release.yml`, which verifies
that the tag points to the qualified `main` commit, runs a final package smoke
test, and creates the GitHub Release assets.

## 10. DUB publication and forward integration

After the tag is visible to the DUB registry:

```bash
dub clean-caches
dub fetch containers-d@0.2.0 --cache=local
```

Verify a clean external consumer against exactly `containers-d@0.2.0`.

After publication, forward-integrate release-only fixes to `develop` without
obscuring later development history.
