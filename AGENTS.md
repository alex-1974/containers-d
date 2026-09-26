# Repository Engineering Context

This repository is part of the `d-geospatial-workspace`.

Before changing architecture, public API, storage or ownership semantics,
safety, allocation behaviour, performance contracts, tests, CI, releases,
repository structure, or toolchain work, read the relevant canonical
workspace documents under `.workspace/`.

Canonical workspace documents:

- `.workspace/README.md`
- `.workspace/ROADMAP.md`
- `.workspace/DESIGN_PRINCIPLES.md`
- `.workspace/DLANG_PRACTICES.md`
- `.workspace/RESEARCH.md`
- `.workspace/QUALITY_GATES.md`
- `.workspace/GIT_GITHUB_WORKFLOW.md`
- `.workspace/REPOSITORY_STANDARD.md`
- `.workspace/TOOLCHAIN_ISSUES.md`

The workspace documents are the shared engineering contract.

Repository-specific documentation may specialize that contract where
containers-d requires it, but must not silently contradict it. Intentional
exceptions must be documented explicitly with their rationale.

containers-d is a generic container library. Storage lifetime, allocation
behaviour, element lifetime, safety attributes, memory layout and performance
are part of the public contract where claimed.

Do not duplicate normative workspace rules in this repository.

When `.workspace/` is unavailable in a standalone clone, follow the tracked
repository documentation and explicitly note that workspace context was not
available.
