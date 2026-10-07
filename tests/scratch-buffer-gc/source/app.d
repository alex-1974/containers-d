module app;

import containers : ScratchBuffer;
import core.memory : GC;
import std.traits : hasIndirections;

private final class ReachabilityProbe
{
    enum Kind
    {
        control,
        first,
        second,
    }

    static __gshared size_t controlFinalized;
    static __gshared size_t firstFinalized;
    static __gshared size_t secondFinalized;

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
            case Kind.first:
                ++firstFinalized;
                break;
            case Kind.second:
                ++secondFinalized;
                break;
        }
    }
}

align(64) private struct OverAlignedReference
{
    ReachabilityProbe reference;
    int cookie;
}

private alias Scratch = ScratchBuffer!OverAlignedReference;

private final class Holder
{
    Scratch scratch;
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

private void collectUntil(ref size_t counter)
{
    foreach (_; 0 .. 64)
    {
        scrubStack();
        GC.collect();

        if (counter >= 1)
            return;
    }
}

void main()
{
    static assert(OverAlignedReference.alignof == 64);
    static assert(hasIndirections!OverAlignedReference);

    ReachabilityProbe.controlFinalized = 0;
    ReachabilityProbe.firstFinalized = 0;
    ReachabilityProbe.secondFinalized = 0;

    createUnrootedControl();

    auto holder = new Holder;
    assert(holder.scratch.tryReserve(1));

    auto first = new ReachabilityProbe(
        ReachabilityProbe.Kind.first,
        0x51);

    assert(holder.scratch.tryPushBack(
        OverAlignedReference(first, 0x51)));

    first = null;

    collectUntil(ReachabilityProbe.controlFinalized);
    assert(ReachabilityProbe.controlFinalized >= 1);

    // External malloc-backed scratch storage is now the only intended root.
    assert(ReachabilityProbe.firstFinalized == 0);
    assert(holder.scratch[0].reference.cookie == 0x51);

    holder.scratch.reset();

    collectUntil(ReachabilityProbe.firstFinalized);
    assert(ReachabilityProbe.firstFinalized >= 1);

    // Replacement must unregister the old range and register/clear the new.
    assert(holder.scratch.tryReserve(4));

    auto second = new ReachabilityProbe(
        ReachabilityProbe.Kind.second,
        0x52);

    assert(holder.scratch.tryPushBack(
        OverAlignedReference(second, 0x52)));

    second = null;

    foreach (_; 0 .. 8)
    {
        scrubStack();
        GC.collect();
    }

    assert(ReachabilityProbe.secondFinalized == 0);
    assert(holder.scratch[0].reference.cookie == 0x52);

    holder.scratch.reset();

    collectUntil(ReachabilityProbe.secondFinalized);
    assert(ReachabilityProbe.secondFinalized >= 1);

    assert(holder !is null);
}
