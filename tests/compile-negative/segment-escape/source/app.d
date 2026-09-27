module app;

import containers : StaticRingBuffer;

int[] escapeSegment() @safe
{
    StaticRingBuffer!(int, 4) buffer;
    assert(buffer.tryPushBack(1));

    // Must fail with DIP1000: returned slice borrows local inline storage.
    return buffer.firstSegment;
}

void main()
{
    auto escaped = escapeSegment();
    assert(escaped.length == 1);
}
