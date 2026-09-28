module containers.inline_storage_gc_probe;

import containers.internal.inline_storage : InlineRawStorage;
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

private alias Storage = InlineRawStorage!(OverAlignedReference, 1);

private final class Holder
{
    Storage storage;
}


pragma(inline, false)
private Holder createBufferedHolder()
{
    auto holder = new Holder;
    auto probe = new ReachabilityProbe(
        ReachabilityProbe.Kind.buffered,
        0x5A17);

    constructBuffered(holder.storage, probe);
    probe = null;

    return holder;
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

private void constructBuffered(
    ref Storage storage,
    ReachabilityProbe probe) @trusted
{
    auto slot = storage.slotPointer(0);
    new (*slot) OverAlignedReference(probe, 0x5A17);
}

pragma(inline, false)
private int bufferedCookie(ref Storage storage) @trusted
{
    return storage.slotPointer(0).reference.cookie;
}

pragma(inline, false)
private void endAndClear(ref Storage storage) @trusted
{
    auto slot = storage.slotPointer(0);
    destroy!false(*slot);
    storage.clearVacatedSlot(0);
}


pragma(inline, false)
private bool slotBytesAreZero(ref Storage storage) @trusted
{
    auto bytes = cast(ubyte*) storage.slotPointer(0);

    foreach (value; bytes[0 .. OverAlignedReference.sizeof])
    {
        if (value != 0)
            return false;
    }

    return true;
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
    static assert(hasIndirections!Storage);

    ReachabilityProbe.controlFinalized = 0;
    ReachabilityProbe.bufferedFinalized = 0;

    createUnrootedControl();

    auto holder = createBufferedHolder();

    const slotAddress =
        cast(size_t) holder.storage.slotPointer(0);
    assert(slotAddress % OverAlignedReference.alignof == 0);

    collectUntilControl();
    assert(ReachabilityProbe.controlFinalized >= 1);

    // The only intended root is now the over-aligned reference held in the
    // GC-heap-resident InlineRawStorage. Its conservative scan shape must keep
    // that object reachable.
    assert(ReachabilityProbe.bufferedFinalized == 0);
    assert(bufferedCookie(holder.storage) == 0x5A17);

    endAndClear(holder.storage);
    assert(slotBytesAreZero(holder.storage));
    assert(ReachabilityProbe.bufferedFinalized == 0);

    // Storage remains alive, but its former slot bytes are zero. The former
    // referent must therefore become collectible.
    collectUntilBuffered();
    assert(ReachabilityProbe.bufferedFinalized >= 1);

    // Keep holder live through the final collection point.
    assert(holder !is null);
}
