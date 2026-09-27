/**
 * High-performance generic container primitives.
 *
 * The current public surface provides $(LREF StaticRingBuffer), a bounded FIFO
 * ring buffer with compile-time capacity and inline storage.
 */
module containers;

public import containers.ring_buffer : StaticRingBuffer;

///
unittest
{
    StaticRingBuffer!(int, 3) buffer;
    assert(buffer.tryPushBack(10));
    assert(buffer.tryPushBack(20));
    buffer.popFront();
    assert(buffer.front == 20);
}
