module app;

import containers : StaticRingBuffer;

struct SafeMovable
{
    int value;

    this(ref return scope SafeMovable rhs) @safe @nogc nothrow
    {
        value = rhs.value;
    }

    this(return scope SafeMovable rhs) @safe @nogc nothrow
    {
        value = rhs.value;
        rhs.value = -1;
    }
}

void main() @safe @nogc nothrow
{
    StaticRingBuffer!(int, 3) buffer;

    assert(buffer.empty);
    assert(buffer.tryPushBack(10));
    assert(buffer.tryPushBack(20));
    assert(buffer.length == 2);
    assert(buffer.front == 10);
    assert(buffer.back == 20);
    assert(buffer[1] == 20);

    auto first = buffer.firstSegment;
    auto second = buffer.secondSegment;
    assert(first.length + second.length == buffer.length);
    assert(first[0] == 10);
    assert(first[1] == 20);
    assert(second.length == 0);

    first[1] = 21;
    assert(buffer.back == 21);

    buffer.popFront();
    assert(buffer.front == 21);

    buffer.clear();
    assert(buffer.empty);

    SafeMovable seed;
    seed.value = 77;

    StaticRingBuffer!(SafeMovable, 2) movable;
    assert(movable.tryPushBack(seed));

    auto moved = __rvalue(movable);
    assert(moved.length == 1);
    assert(moved.front.value == 77);
}
