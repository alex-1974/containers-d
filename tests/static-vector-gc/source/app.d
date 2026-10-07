module app;

import containers.static_vector : StaticVector;
import core.memory : GC;
import std.traits : hasIndirections;

private final class ReachabilityProbe
{
    enum Kind
    {
        control,
        vector,
    }

    static __gshared size_t controlFinalized;
    static __gshared size_t vectorFinalized;

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

            case Kind.vector:
                ++vectorFinalized;
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

private alias Vector =
    StaticVector!(OverAlignedReference, 1);

private final class Holder
{
    Vector vector;
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
private Holder createVectorHolder()
{
    auto holder = new Holder;

    auto probe = new ReachabilityProbe(
        ReachabilityProbe.Kind.vector,
        0x5A17);

    holder.vector.pushBack(
        OverAlignedReference(probe, 0x5A17));

    probe = null;

    return holder;
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

private void collectUntilVector()
{
    foreach (_; 0 .. 64)
    {
        scrubStack();
        GC.collect();

        if (ReachabilityProbe.vectorFinalized >= 1)
            return;
    }
}

void main()
{
    static assert(OverAlignedReference.alignof == 64);
    static assert(hasIndirections!OverAlignedReference);
    static assert(hasIndirections!Vector);

    ReachabilityProbe.controlFinalized = 0;
    ReachabilityProbe.vectorFinalized = 0;

    createUnrootedControl();
    auto holder = createVectorHolder();

    assert(holder.vector.length == 1);

    const slotAddress =
        cast(size_t) &holder.vector[0];

    assert(
        slotAddress %
        OverAlignedReference.alignof == 0);

    collectUntilControl();
    assert(ReachabilityProbe.controlFinalized >= 1);

    // The vector now owns the only intended GC-visible reference.
    assert(ReachabilityProbe.vectorFinalized == 0);
    assert(holder.vector[0].reference.cookie == 0x5A17);

    holder.vector.clear();
    assert(holder.vector.empty);
    assert(ReachabilityProbe.vectorFinalized == 0);

    // The vector object remains alive, but clearing it must remove the stale
    // pointer representation from the vacated inline slot.
    collectUntilVector();
    assert(ReachabilityProbe.vectorFinalized >= 1);

    // Keep the holder alive through the final collection point.
    assert(holder !is null);
}
