module app;

import containers.research.static_vector : StaticVector;

private void binary64ConsumerProbe(
    ref StaticVector!(double, 4) vector)
    pure nothrow @safe @nogc
{
    assert(vector.empty);

    vector.pushBack(1.0);
    vector.pushBack(0x1p-52);
    vector.pushBack(-0x1p-104);

    assert(vector.length == 3);
    assert(vector[0] == 1.0);
    assert(vector[1] == 0x1p-52);
    assert(vector[2] == -0x1p-104);

    vector.clear();
    assert(vector.empty);
}

void main()
{
    StaticVector!(double, 4) vector;
    binary64ConsumerProbe(vector);

    static assert(StaticVector!(double, 4).capacity == 4);
    static assert(
        StaticVector!(double, 4).sizeof ==
        4 * double.sizeof + size_t.sizeof);
}
