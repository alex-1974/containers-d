module app;

import containers.static_vector : StaticVector;

int[] escapeStaticVectorSlice() @safe
{
    StaticVector!(int, 4) vector;
    vector.pushBack(1);

    // Must fail under DIP1000: the slice borrows local inline storage.
    return vector[];
}

void main()
{
    auto escaped = escapeStaticVectorSlice();
    assert(escaped.length == 1);
}
