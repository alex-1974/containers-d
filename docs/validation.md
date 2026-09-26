# Validation

containers-d follows `.workspace/QUALITY_GATES.md`.

Container validation is expected to cover, where applicable:

- structural invariants;
- empty/full transitions;
- wraparound;
- element construction and destruction;
- copy and move semantics;
- alignment;
- bounds and invalid operations;
- allocation behaviour;
- attribute claims such as `@safe`, `@nogc`, `nothrow` and CTFE;
- adversarial operation sequences;
- performance evidence for claimed hot paths.

Observed performance is evidence, not a substitute for correctness.
