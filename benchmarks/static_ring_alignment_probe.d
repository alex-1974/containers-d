/**
 * M4.2 alignment probe comparing the current StaticRingBuffer representation
 * with the reusable InlineRawStorage prototype.
 */
module containers.static_ring_alignment_probe;

import containers.internal.inline_storage : InlineRawStorage;
import containers.ring_buffer : StaticRingBuffer;
import std.stdio : writeln;

align(64) struct OverAligned64
{
    ulong value;
}

private alias CurrentRing = StaticRingBuffer!(OverAligned64, 3);
private alias CandidateStorage = InlineRawStorage!(OverAligned64, 3);

private struct RingHolder
{
    ubyte prefix;
    CurrentRing ring;
}

private struct StorageHolder
{
    ubyte prefix;
    CandidateStorage storage;
}

void main()
{
    writeln("element-align ", OverAligned64.alignof);
    writeln("ring-align ", CurrentRing.alignof);
    writeln("ring-holder-offset ", RingHolder.ring.offsetof);
    writeln("ring-sufficient ",
        CurrentRing.alignof >= OverAligned64.alignof &&
        RingHolder.ring.offsetof % OverAligned64.alignof == 0 ? 1 : 0);

    writeln("storage-align ", CandidateStorage.alignof);
    writeln("storage-holder-offset ", StorageHolder.storage.offsetof);
    writeln("storage-sufficient ",
        CandidateStorage.alignof >= OverAligned64.alignof &&
        StorageHolder.storage.offsetof % OverAligned64.alignof == 0 ? 1 : 0);

    // The research candidate itself must provide a type-level guarantee rather
    // than relying on a particular stack address.
    assert(CandidateStorage.alignof >= OverAligned64.alignof);
    assert(StorageHolder.storage.offsetof % OverAligned64.alignof == 0);
}
