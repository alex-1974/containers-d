# Security Policy

Security-sensitive findings involving memory safety, lifetime escape, raw
storage, GC range registration or `@trusted` boundaries should not be
disclosed in a public issue before there has been a reasonable opportunity to
assess and address them.

For ordinary correctness bugs, API questions and non-sensitive defects, use the
GitHub issue tracker.

`containers-d` is a source library. The v0.x line does not provide a binary
ABI compatibility guarantee; consumers are expected to rebuild against the
version they use.
