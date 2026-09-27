module app;

import containers : RingBuffer;

int[] escapeRuntimeSegment() @safe
{
    auto buffer = RingBuffer!int(4);
    assert(buffer.tryPushBack(1));

    // Must fail under DIP1000: the slice borrows storage owned by the local
    // buffer and becomes invalid when that owner is destroyed.
    return buffer.firstSegment;
}

void main()
{
    auto escaped = escapeRuntimeSegment();
    assert(escaped.length == 1);
}
