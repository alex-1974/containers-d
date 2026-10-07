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

pragma(inline, false)
private Holder createFirstHolder()
{
    auto holder = new Holder;
    assert(holder.scratch.tryReserve(1));

    auto probe = new ReachabilityProbe(
        ReachabilityProbe.Kind.first,
        0x51);

    assert(holder.scratch.tryPushBack(
        OverAlignedReference(probe, 0x51)));

    probe = null;
    return holder;
}

pragma(inline, false)
private void populateSecond(ref Scratch scratch)
{
    assert(scratch.tryReserve(4));

    auto probe = new ReachabilityProbe(
        ReachabilityProbe.Kind.second,
        0x52);

    assert(scratch.tryPushBack(
        OverAlignedReference(probe, 0x52)));

    probe = null;
}

pragma(inline, false)
private int bufferedCookie(ref Scratch scratch)
{
    return scratch[0].reference.cookie;
}

pragma(inline, false)
private void resetScratch(ref Scratch scratch)
{
    scratch.reset();
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

    auto holder = createFirstHolder();

    collectUntil(ReachabilityProbe.controlFinalized);
    assert(ReachabilityProbe.controlFinalized >= 1);

    // External malloc-backed scratch storage is now the only intended root.
    assert(ReachabilityProbe.firstFinalized == 0);
    assert(bufferedCookie(holder.scratch) == 0x51);

    resetScratch(holder.scratch);

    collectUntil(ReachabilityProbe.firstFinalized);
    assert(ReachabilityProbe.firstFinalized >= 1);

    // Replacement must unregister the old range and register/clear the new.
    populateSecond(holder.scratch);

    foreach (_; 0 .. 8)
    {
        scrubStack();
        GC.collect();
    }

    assert(ReachabilityProbe.secondFinalized == 0);
    assert(bufferedCookie(holder.scratch) == 0x52);

    resetScratch(holder.scratch);

    collectUntil(ReachabilityProbe.secondFinalized);
    assert(ReachabilityProbe.secondFinalized >= 1);

    assert(holder !is null);
}
