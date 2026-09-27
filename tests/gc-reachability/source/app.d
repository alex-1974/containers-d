module app;

import containers : RingBuffer;
import core.memory : GC;

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
private void createUnrootedControl()
{
    auto control = new ReachabilityProbe(
        ReachabilityProbe.Kind.control,
        0x11);

    assert(control.cookie == 0x11);
    control = null;
}

pragma(inline, false)
private RingBuffer!ReachabilityProbe createBufferedProbe()
{
    auto buffer = RingBuffer!ReachabilityProbe(2);
    auto probe = new ReachabilityProbe(
        ReachabilityProbe.Kind.buffered,
        0x5A17);

    assert(buffer.tryPushBack(probe));
    probe = null;

    return __rvalue(buffer);
}

pragma(inline, false)
private int bufferedCookie(ref RingBuffer!ReachabilityProbe buffer)
{
    return buffer.front.cookie;
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
    ReachabilityProbe.controlFinalized = 0;
    ReachabilityProbe.bufferedFinalized = 0;

    createUnrootedControl();
    auto buffer = createBufferedProbe();

    // Establish that collection/finalization actually occurred.
    collectUntilControl();
    assert(ReachabilityProbe.controlFinalized >= 1);

    // The only intended root for this object is the class reference stored in
    // RingBuffer's registered external backing allocation.
    assert(ReachabilityProbe.bufferedFinalized == 0);
    assert(bufferedCookie(buffer) == 0x5A17);

    // Removing the class reference ends only the stored reference value. It
    // must not explicitly finalize the referenced object.
    buffer.popFront();
    assert(buffer.empty);
    assert(ReachabilityProbe.bufferedFinalized == 0);

    // The vacated slot was zeroed. Once temporary stack remnants are scrubbed,
    // the former referent must become collectible.
    collectUntilBuffered();
    assert(ReachabilityProbe.bufferedFinalized >= 1);
}
