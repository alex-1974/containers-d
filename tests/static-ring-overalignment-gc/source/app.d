module containers.static_ring_overalignment_gc_probe;

import containers : StaticRingBuffer;
import core.memory : GC;
import std.traits : hasIndirections;

private final class ReachabilityProbe
{
    enum Kind
    {
        control,
        buffered,
    }

    static __gshared size_t controlFinalized;
    static __gshared size_t bufferedFinalized;

    Kind kind;
    int cookie;

    this(Kind kind, int cookie)
    {
        this.kind = kind;
        this.cookie = cookie;
    }

    ~this()
    {
        final switch (kind)
        {
            case Kind.control:
                ++controlFinalized;
                break;

            case Kind.buffered:
                ++bufferedFinalized;
                break;
        }
    }
}

align(64) private struct OverAlignedReference
{
    ReachabilityProbe reference;
    int cookie;

    this(ReachabilityProbe reference, int cookie)
    {
        this.reference = reference;
        this.cookie = cookie;
    }
}

private alias Buffer = StaticRingBuffer!(OverAlignedReference, 1);

private final class Holder
{
    Buffer buffer;
}

private __gshared size_t stackSink;

pragma(inline, false)
private void scrubStack() @nogc nothrow
{
    size_t[4096] scratch;

    foreach (i, ref value; scratch)
        value = (i + 1) * 0x9E37_79B9;

    stackSink ^= scratch[$ - 1];
}

pragma(inline, false)
private Holder createBufferedHolder()
{
    auto holder = new Holder;
    auto probe = new ReachabilityProbe(
        ReachabilityProbe.Kind.buffered,
        0x5A17);

    assert(holder.buffer.tryPushBack(
        OverAlignedReference(probe, 0x5A17)));

    probe = null;
    return holder;
}

pragma(inline, false)
private void createUnrootedControl()
{
    auto control = new ReachabilityProbe(
        ReachabilityProbe.Kind.control,
        0x11);

    assert(control.cookie == 0x11);
    control = null;
}

private void collectUntilControl()
{
    foreach (_; 0 .. 64)
    {
        scrubStack();
        GC.collect();

        if (ReachabilityProbe.controlFinalized >= 1)
            return;
    }
}

private void collectUntilBuffered()
{
    foreach (_; 0 .. 64)
    {
        scrubStack();
        GC.collect();

        if (ReachabilityProbe.bufferedFinalized >= 1)
            return;
    }
}

void main()
{
    static assert(OverAlignedReference.alignof == 64);
    static assert(hasIndirections!OverAlignedReference);
    static assert(hasIndirections!Buffer);

    ReachabilityProbe.controlFinalized = 0;
    ReachabilityProbe.bufferedFinalized = 0;

    createUnrootedControl();
    auto holder = createBufferedHolder();

    const slotAddress = cast(size_t) &holder.buffer[0];
    assert(slotAddress % OverAlignedReference.alignof == 0);

    collectUntilControl();
    assert(ReachabilityProbe.controlFinalized >= 1);

    // The only intended root is the reference stored in the live over-aligned
    // StaticRingBuffer slot.
    assert(ReachabilityProbe.bufferedFinalized == 0);
    assert(holder.buffer.front.reference.cookie == 0x5A17);
    assert(holder.buffer.front.cookie == 0x5A17);

    holder.buffer.popFront();
    assert(holder.buffer.empty);
    assert(ReachabilityProbe.bufferedFinalized == 0);

    // The holder and its raw storage remain live, but popFront() must clear the
    // vacated pointer-bearing slot so the former referent can be collected.
    collectUntilBuffered();
    assert(ReachabilityProbe.bufferedFinalized >= 1);

    assert(holder !is null);
}
