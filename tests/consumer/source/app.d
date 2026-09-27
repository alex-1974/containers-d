module app;

import containers : StaticRingBuffer;

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
    assert(second.empty);

    first[1] = 21;
    assert(buffer.back == 21);

    buffer.popFront();
    assert(buffer.front == 21);

    buffer.clear();
    assert(buffer.empty);
}
