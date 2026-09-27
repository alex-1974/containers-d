/**
 * High-performance generic container primitives.
 *
 * Public ring-buffer families:
 *
 * - $(LREF StaticRingBuffer): compile-time capacity with inline storage;
 * - $(LREF RingBuffer): runtime capacity with one owned backing allocation.
 */
module containers;

public import containers.ring_buffer : StaticRingBuffer;
public import containers.runtime_ring_buffer : RingBuffer;

///
unittest
{
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
