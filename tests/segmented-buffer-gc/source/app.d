module app;

import containers : SegmentedBuffer;
import core.memory : GC;
import std.traits : hasIndirections;

private final class Probe
{
    static __gshared size_t finalized;
    int cookie;

    this(int cookie) { this.cookie = cookie; }
    ~this() { ++finalized; }
}

align(64) private struct AlignedReference
{
    Probe reference;
    int cookie;

    this(ref const AlignedReference rhs)
    {
        reference = cast(Probe) rhs.reference;
        cookie = rhs.cookie;
    }

}

pragma(inline, false)
private void scrubStack() @nogc nothrow
{
    size_t[16384] values;
    foreach (i, ref value; values)
        value = i * 0x9E3779B9;
}

private void collectUntilFinalized()
{
    foreach (_; 0 .. 64)
    {
        scrubStack();
        GC.collect();
        if (Probe.finalized != 0)
            return;
    }
}

void main()
{
    static assert(AlignedReference.alignof == 64);
    static assert(hasIndirections!AlignedReference);

    Probe.finalized = 0;
    auto buffer = SegmentedBuffer!AlignedReference(1, 2);
    auto probe = new Probe(0x5A17);
    assert(buffer.append([AlignedReference(probe, 0x5A17)]) == 1);
    probe = null;

    auto first = buffer.segment(0);
    assert(cast(size_t) first.ptr % AlignedReference.alignof == 0);
    assert(first[0].cookie == 0x5A17);

    scrubStack();
    GC.collect();
    assert(Probe.finalized == 0);

    assert(buffer.consume(1) == 1);
    assert(Probe.finalized == 0);
    // The borrowed view is invalid for consumer use after consume, but the
    // test may inspect the raw slot to verify that its stale GC reference was
    // cleared by the container.
    assert(first[0].reference is null);
    collectUntilFinalized();
}
