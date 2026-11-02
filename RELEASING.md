# Releasing containers-d

This document defines the release procedure for the independently versioned
`containers-d` package.

The first release is `v0.1.0`. It publishes only the admitted static- and
runtime-capacity ring-buffer families.

## Repository-specific promotion policy for protected `main`

`containers-d` intentionally specializes the workspace default merge strategy
for release and hotfix promotion.

The repository's protected `main` branch enforces linear history. Repository
settings allow merge commits in general, but promotion of the v0.2.0 release
demonstrated that `main` rejects a merge commit with:

```text
This branch must not contain merge commits
```

No repository rulesets are currently defined. The GitHub integration cannot
read the administrative branch-protection endpoint, but the enforced behavior
is authoritative for this repository.

Therefore:

- `release/* -> main` uses a **squash merge**;
- `hotfix/* -> main` uses a **squash merge**;
- the source release/hotfix branch head MUST pass every applicable exact-head
  Release Gate before promotion;
- the promoted `main` commit MUST have the same qualified tree as the source
  head; verify tree identity explicitly;
- the full Release Gate MUST pass again on the promoted `main` commit;
- only that green `main` commit may receive the annotated/signed release tag;
- no force-push, history rewrite, or weakening of `main` protection is part
  of this specialization.

For a release branch:

```bash
SOURCE_COMMIT="$(git rev-parse release/X.Y)"
SOURCE_TREE="$(git rev-parse "$SOURCE_COMMIT^{tree}")"

# Merge the release PR using GitHub squash merge, then:
git fetch origin main
MAIN_COMMIT="$(git rev-parse origin/main)"
MAIN_TREE="$(git rev-parse "$MAIN_COMMIT^{tree}")"

test "$MAIN_TREE" = "$SOURCE_TREE"
```

The same tree-identity rule applies to a hotfix branch cut from the affected
release tag. After publication, forward-integrate the resulting release/hotfix
state into `develop` through the normal PR/cherry-pick path.

This is an explicit repository-specific exception to the workspace default
`release/* -> main` / `hotfix/* -> main` merge-commit strategy. The v0.2.0
promotion remains grandfathered evidence of the protection rule that motivated
the exception.

## 1. Release candidate

Release hardening is tracked by issue #21 on:

```text
release/v0.1.0
```

The branch starts from the M3-complete `develop` state and is intentionally a
real stabilization branch: public API is frozen except for release-blocking
contract corrections.

The full Release Gate runs on pushes to `release/**`. Do not establish the
first `main` state until every required release job is green.

## 2. Required qualification

Before promotion, require:

- six-compiler controlled matrix:
  - DMD 2.111.0
  - DMD 2.112.1
  - DMD 2.113.0
  - LDC 1.41.0
  - LDC 1.42.0
  - LDC 1.43.0
- normal and DIP1000 unit tests;
- package-root external consumer, with and without DIP1000;
- runtime GC reachability integration;
- negative borrowed-segment compile tests;
- release build and Ddoc build;
- consumer archive audit and archive-only smoke test;
- configured portability jobs.

Record the exact qualified commit:

```bash
RELEASE_COMMIT="$(git rev-parse HEAD)"
printf '%s\n' "$RELEASE_COMMIT"
```

## 3. Initial main bootstrap

`main` does not exist before the first qualified release.

After the release candidate is green, create `main` at exactly
`RELEASE_COMMIT`. Configure it as the protected release line before further
changes are accepted:

- PR/release integration only;
- Release Gate required;
- no force-push;
- no deletion.

The push creating the first `main` state runs the Release Gate again. The
release tag is created only from that same green commit.

## 4. Final local verification

From a clean checkout of the release commit:

```bash
dub describe
dub test --compiler=dmd --force
dub build --build=release --compiler=dmd --force

tmp="$(mktemp -d)"
git archive HEAD | tar -xf - -C "$tmp"
(cd "$tmp" && dub test --compiler=dmd --force)
```

The exported archive must contain consumer source/metadata only; repository
tests, benchmarks, evidence and CI configuration are intentionally excluded.

## 5. Create the release tag

Release tags MUST be annotated and SHOULD be signed.

```bash
git switch main
git pull --ff-only origin main

RELEASE_COMMIT="$(git rev-parse HEAD)"

git tag -s v0.1.0 "$RELEASE_COMMIT" -m "containers-d v0.1.0"
git show --no-patch --decorate v0.1.0
git rev-parse v0.1.0^{commit}
test "$(git rev-parse v0.1.0^{commit})" = "$RELEASE_COMMIT"

git push origin v0.1.0
```

If signing is temporarily unavailable, use an annotated tag (`git tag -a`)
and record the reason rather than creating a lightweight tag.

Tag publication triggers `.github/workflows/release.yml`, which verifies that
the tag commit is exactly `origin/main`, performs a final package smoke test,
creates the GitHub Release and attaches the consumer archive plus SHA-256.

## 6. DUB publication

The DUB registry derives numbered releases from SemVer Git tags.

Check whether the package is already registered:

```bash
dub search containers-d
```

If it is not registered, register:

```text
package: containers-d
repository: https://github.com/alex-1974/containers-d
```

After registry discovery:

```bash
dub clean-caches
dub fetch containers-d@0.1.0 --cache=local
```

Then create a clean temporary consumer that depends on exactly
`containers-d@0.1.0` from the registry and imports both public buffer families.

The release is complete only after that registry-backed consumer succeeds.

## 7. Forward integration

After publication, forward-integrate the release result to `develop` if the
release branch contains commits not already present there. Do not merge the
release line wholesale in a way that obscures later development history.


## Stable API documentation

Stable API documentation is published to GitHub Pages from qualified release
tags, not from the moving `develop` branch.

The Pages workflow:

1. resolves an explicit `vMAJOR.MINOR.PATCH` release tag;
2. extracts that immutable tagged source tree;
3. builds the rendered DDox API documentation with the release documentation
   compiler baseline;
4. verifies that all six published container families appear in the rendered
   HTML;
5. publishes both the stable root and a versioned
   `/<release-tag>/` documentation tree.

For a newly created release tag the workflow runs automatically once this
workflow is part of that tagged release. For the already-published v0.2.0
bootstrap, dispatch `pages.yml` manually with `version=v0.2.0`.

Post-release verification must confirm that the Pages URL is reachable and
serves documentation generated from the intended release tag.
