# Tutorial — choose and use a ring buffer

`containers-d` v0.1 provides two bounded single-threaded FIFO ring buffers.

Use `StaticRingBuffer!(T, Capacity)` when the maximum capacity is known at
compile time and inline storage is desirable. Use `RingBuffer!T` when capacity
is selected at runtime and one owned backing allocation is appropriate.

## Static capacity

```d
import containers : StaticRingBuffer;

StaticRingBuffer!(int, 4) queue;

assert(queue.tryPushBack(10));
assert(queue.tryPushBack(20));
assert(queue.front == 10);

queue.popFront();
assert(queue.front == 20);
```

`tryPushBack` never overwrites existing contents. When the buffer is full it
returns `false`.

## Runtime capacity

```d
import containers : RingBuffer;

auto queue = RingBuffer!int(1024);

assert(queue.tryPushBack(10));
assert(queue.tryPushBack(20));
queue.popFront();

assert(queue.front == 20);
```

A positive runtime capacity acquires one backing block. Ordinary push, pop and
clear operations retain that capacity.

## Preconditions

`front` and `back` require a non-empty buffer. Indexed access requires
`index < length`. These are preconditions, not fallible checked operations.

## Ownership

`StaticRingBuffer` owns its inline storage and may be copied when `T` is
copyable. `RingBuffer` has unique runtime-storage ownership: implicit copy and
identity assignment are disabled, while whole-buffer move transfers ownership
in O(1).

For wrapped bulk processing, continue with the how-to guide in
`docs/how-to/README.md`.
