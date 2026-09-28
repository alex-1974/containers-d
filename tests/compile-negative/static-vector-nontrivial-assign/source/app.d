module app;

import containers.static_vector : StaticVector;

private struct Tracked
{
    int value;

    ~this() @safe @nogc nothrow {}
}

void main()
{
    StaticVector!(Tracked, 2) lhs;
    StaticVector!(Tracked, 2) rhs;

    // Must fail until nontrivial destination cleanup/self-assignment semantics
    // are explicitly qualified.
    lhs = rhs;
}
