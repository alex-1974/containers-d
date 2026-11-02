module app;

import containers : SegmentedByteBuffer;

const(ubyte)[] escapeSegment() @safe
{
    auto buffer = SegmentedByteBuffer(4, 8);
    assert(buffer.append([1, 2, 3]) == 3);
    // Must fail under DIP1000: the slice borrows local owner storage.
    return buffer.segment(0);
}

void main()
{
    auto escaped = escapeSegment();
    assert(escaped.length == 3);
}
