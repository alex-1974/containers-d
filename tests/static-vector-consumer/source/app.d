module app;

import containers.static_vector : StaticVector;

private void binary64Surface(
    ref StaticVector!(double, 4) vector)
    pure nothrow @safe @nogc
{
    assert(vector.empty);
    assert(vector.capacity == 4);

    vector.pushBack(1.0);
    vector.pushBack(2.0);

    assert(vector.length == 2);
    assert(vector.front == 1.0);
    assert(vector.back == 2.0);
    assert(vector[0] == 1.0);
    assert(vector[1] == 2.0);

    auto live = vector[];
    assert(live.length == 2);
    assert(live.ptr is &vector[0]);

    live[1] = 3.0;
    assert(vector.back == 3.0);

    vector.popBack();
    assert(vector.length == 1);

    vector.clear();
    assert(vector.empty);
}

private void checkedInsertion()
    @safe @nogc nothrow
{
    StaticVector!(int, 2) vector;

    assert(vector.tryPushBack(10));
    assert(vector.tryPushBack(20));
    assert(!vector.tryPushBack(30));

    assert(vector.full);
    assert(vector[] == [10, 20]);
}

void main()
{
    StaticVector!(double, 4) vector;
    binary64Surface(vector);
    checkedInsertion();

    const StaticVector!(double, 4) constVector = vector;
    auto borrowed = constVector[];
    assert(borrowed.length == 0);

    static assert(StaticVector!(double, 4).capacity == 4);
    static assert(
        StaticVector!(double, 4).sizeof ==
        4 * double.sizeof + size_t.sizeof);
}
