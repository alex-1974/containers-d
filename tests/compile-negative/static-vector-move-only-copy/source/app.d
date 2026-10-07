module app;

import containers.static_vector : StaticVector;

private struct MoveOnly
{
    int value;

    @disable this(ref return scope MoveOnly rhs);

    this(return scope MoveOnly rhs) @safe @nogc nothrow
    {
        value = rhs.value;
        rhs.value = -1;
    }
}

void main()
{
    StaticVector!(MoveOnly, 2) source;

    // Must fail: T is not copy-constructible.
    auto copied = source;
}
