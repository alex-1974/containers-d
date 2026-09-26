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

    buffer.popFront();
    assert(buffer.front == 20);

    buffer.clear();
    assert(buffer.empty);
}
