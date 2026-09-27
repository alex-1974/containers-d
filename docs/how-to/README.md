# How-to — process wrapped contents without copying

Both public ring buffers expose their logical FIFO contents as at most two
contiguous borrowed slices:

```d
auto first = buffer.firstSegment;
auto second = buffer.secondSegment;
```

The logical order is always exactly:

```text
first followed by second
```

and:

```d
assert(first.length + second.length == buffer.length);
```

This makes scatter/gather-style processing possible without first linearizing
the ring.

## Example

```d
import containers : StaticRingBuffer;

StaticRingBuffer!(int, 4) buffer;

foreach (value; 1 .. 5)
    assert(buffer.tryPushBack(value));

buffer.popFront();
assert(buffer.tryPushBack(5));

foreach (value; buffer.firstSegment)
{
    // process first contiguous physical region
}

foreach (value; buffer.secondSegment)
{
    // process wrapped continuation
}
```

## Borrowing and invalidation

The slices borrow storage from the buffer. Do not retain them across a
successful structural mutation, owner move or destruction.

A failed `tryPushBack` on an already-full buffer does not mutate the logical
sequence and therefore does not invalidate existing segment slices.

With DIP1000 enabled, the package's negative compile tests verify that borrowed
segment slices cannot escape a shorter-lived local owner.
