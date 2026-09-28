/**
 * High-performance generic container primitives.
 *
 * Public container families:
 *
 * - $(LREF StaticVector): compile-time fixed-capacity contiguous inline vector;
 * - $(LREF StaticRingBuffer): compile-time capacity inline FIFO ring buffer;
 * - $(LREF RingBuffer): runtime capacity FIFO with one owned backing allocation.
 */
module containers;

public import containers.ring_buffer : StaticRingBuffer;
public import containers.runtime_ring_buffer : RingBuffer;
public import containers.static_vector : StaticVector;

///
unittest
{
    StaticVector!(int, 3) vector;
    vector.pushBack(1);
    vector.pushBack(2);
    assert(vector[] == [1, 2]);

    StaticRingBuffer!(int, 3) fixed;
    assert(fixed.tryPushBack(10));
    assert(fixed.tryPushBack(20));
    fixed.popFront();
    assert(fixed.front == 20);

    auto runtime = RingBuffer!int(3);
    assert(runtime.tryPushBack(30));
    assert(runtime.tryPushBack(40));
    runtime.popFront();
    assert(runtime.front == 40);
}
