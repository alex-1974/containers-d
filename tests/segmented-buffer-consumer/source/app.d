module app;

import containers : SegmentedBuffer, SegmentedByteBuffer;

private void testByteConsumer()
{
    auto buffer = SegmentedByteBuffer(4, 10);
    const ubyte[] chunk = [1, 2, 3, 4, 5, 6];

    assert(buffer.append(chunk) == 6);
    assert(buffer.segmentCount == 2);
    assert(buffer.segment(0) == [1, 2, 3, 4]);
    assert(buffer.segment(1) == [5, 6]);
    assert(buffer.consume(5) == 5);
    assert(buffer.length == 1);
}

private struct Record
{
    int value;
}

private void testGenericConsumer()
{
    auto buffer = SegmentedBuffer!Record(2, 4);
    Record[3] records = [Record(1), Record(2), Record(3)];

    assert(buffer.append(records[]) == 3);
    assert(buffer.segment(0)[0].value == 1);
    assert(buffer.segment(1)[0].value == 3);
}

void main()
{
    testByteConsumer();
    testGenericConsumer();
}
