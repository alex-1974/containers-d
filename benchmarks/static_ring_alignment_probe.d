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

    StorageHolder storageHolder;
    const storageSlotAddress =
        cast(size_t) storageHolder.storage.slotPointer(0);

    writeln("storage-slot-address-mod-element-align ",
        storageSlotAddress % OverAligned64.alignof);
    writeln("storage-slot-sufficient ",
        storageSlotAddress % OverAligned64.alignof == 0 ? 1 : 0);

    // The reusable storage candidate deliberately does not require the wrapper
    // field itself to inherit T's over-alignment. It reserves slack and aligns
    // the actual T slot from the runtime address.
    assert(storageSlotAddress % OverAligned64.alignof == 0);

    // The current ring figures remain observational. Issue #31 owns its
    // released-contract correction.
}
