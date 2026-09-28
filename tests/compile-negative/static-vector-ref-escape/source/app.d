module app;

import containers.static_vector : StaticVector;

ref int escapeStaticVectorRef() @safe
{
    StaticVector!(int, 4) vector;
    vector.pushBack(1);

    // Must fail under DIP1000: the reference borrows local inline storage.
    return vector[0];
}

void main()
{
    ref value = escapeStaticVectorRef();
    assert(value == 1);
}
