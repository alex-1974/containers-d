/**
 * Issue #31 alignment matrix for the released StaticRingBuffer representation
 * and compiler/target-qualified InlineRawStorage candidates.
 */
module containers.static_ring_alignment_probe;

import containers.internal.inline_storage : InlineRawStorage;
import containers.internal.target_capabilities :
    nativePointerAlignment,
    qualifiedInlineEmbeddedAlignment;
import containers.ring_buffer : StaticRingBuffer;
import std.stdio : writeln;
import std.traits : hasIndirections;

version (LDC)
    private enum string compilerLabel = "ldc";
else version (DigitalMars)
    private enum string compilerLabel = "dmd";
else
    private enum string compilerLabel = "other";

version (X86_64)
    private enum string architectureLabel = "x86_64";
else version (AArch64)
    private enum string architectureLabel = "aarch64";
else
    private enum string architectureLabel = "other";

private struct NormalAligned
{
    ulong value;
}

align(64) private struct OverAligned64
{
    ulong value;
}

align(64) private struct OverAlignedReference64
{
    Object reference;
    ulong value;
}

private alias CurrentRing = StaticRingBuffer!(OverAligned64, 3);
private alias CandidateStorage = InlineRawStorage!(OverAligned64, 3);
private alias ReferenceStorage = InlineRawStorage!(OverAlignedReference64, 2);
private alias NormalStorage = InlineRawStorage!(NormalAligned, 3);

/**
 * Deliberately forced native representation used only to observe whether the
 * current compiler/target propagates an over-aligned field through embedding.
 * No production code depends on this type.
 */
private struct NativeProbeStorage(T, size_t Capacity)
{
    align(T.alignof) ubyte[T.sizeof * Capacity] bytes;
}

private alias ForcedNativeStorage = NativeProbeStorage!(OverAligned64, 3);

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

private struct ReferenceStorageHolder
{
    ubyte prefix;
    ReferenceStorage storage;
}

private struct ForcedNativeHolder
{
    ubyte prefix;
    ForcedNativeStorage storage;
}

private size_t addressMod(const void* address, size_t alignment)
{
    return cast(size_t) address % alignment;
}

void main()
{
    static assert(!NormalStorage.usesDynamicAlignment);
    static assert(NormalStorage.sizeof ==
        NormalAligned.sizeof * NormalStorage.capacity);
    static assert(hasIndirections!OverAlignedReference64);
    static assert(hasIndirections!ReferenceStorage);

    writeln("compiler ", compilerLabel);
    writeln("architecture ", architectureLabel);
    writeln("native-pointer-align ", nativePointerAlignment);
    writeln("qualified-inline-embedded-align ",
        qualifiedInlineEmbeddedAlignment);

    writeln("element-align ", OverAligned64.alignof);
    writeln("ring-align ", CurrentRing.alignof);
    writeln("ring-holder-offset ", RingHolder.ring.offsetof);
    writeln("ring-native-wrapper-contract-sufficient ",
        CurrentRing.alignof >= OverAligned64.alignof &&
        RingHolder.ring.offsetof % OverAligned64.alignof == 0 ? 1 : 0);
    writeln("ring-representation-dynamic ",
        OverAligned64.alignof > qualifiedInlineEmbeddedAlignment ? 1 : 0);

    RingHolder[2] ringHolders;
    foreach (holderIndex, ref holder; ringHolders)
    {
        writeln("ring-holder-array-", holderIndex,
            "-address-mod-element-align ",
            addressMod(&holder.ring, OverAligned64.alignof));

        foreach (slotIndex; 0 .. CurrentRing.capacity)
        {
            OverAligned64 value;
            value.value = holderIndex * 100 + slotIndex + 1;
            assert(holder.ring.tryPushBack(value));
        }

        foreach (logicalIndex; 0 .. holder.ring.length)
        {
            const address =
                cast(size_t) &holder.ring[logicalIndex];
            writeln("ring-holder-array-", holderIndex,
                "-logical-", logicalIndex,
                "-slot-mod-element-align ",
                address % OverAligned64.alignof);
            assert(address % OverAligned64.alignof == 0);
        }

        // Force a wrapped logical layout and re-check the exposed live slots.
        holder.ring.popFront();
        OverAligned64 wrapped;
        wrapped.value = holderIndex * 100 + 99;
        assert(holder.ring.tryPushBack(wrapped));

        foreach (logicalIndex; 0 .. holder.ring.length)
        {
            const address =
                cast(size_t) &holder.ring[logicalIndex];
            writeln("ring-holder-array-", holderIndex,
                "-wrapped-logical-", logicalIndex,
                "-slot-mod-element-align ",
                address % OverAligned64.alignof);
            assert(address % OverAligned64.alignof == 0);
        }
    }

    CurrentRing[2] ringArray;
    foreach (ringIndex, ref ring; ringArray)
    {
        OverAligned64 value;
        value.value = ringIndex + 1;
        assert(ring.tryPushBack(value));

        const address = cast(size_t) &ring[0];
        writeln("ring-array-", ringIndex,
            "-front-slot-mod-element-align ",
            address % OverAligned64.alignof);
        assert(address % OverAligned64.alignof == 0);
    }

    writeln("ring-slot-sufficient 1");

    writeln("forced-native-align ", ForcedNativeStorage.alignof);
    writeln("forced-native-holder-offset ",
        ForcedNativeHolder.storage.offsetof);

    ForcedNativeHolder forcedNativeHolder;
    writeln("forced-native-address-mod-element-align ",
        addressMod(&forcedNativeHolder.storage, OverAligned64.alignof));
    writeln("forced-native-sufficient ",
        ForcedNativeStorage.alignof >= OverAligned64.alignof &&
        ForcedNativeHolder.storage.offsetof % OverAligned64.alignof == 0 &&
        addressMod(&forcedNativeHolder.storage, OverAligned64.alignof) == 0
            ? 1 : 0);

    writeln("storage-dynamic ",
        CandidateStorage.usesDynamicAlignment ? 1 : 0);
    writeln("storage-align ", CandidateStorage.alignof);
    writeln("storage-size ", CandidateStorage.sizeof);
    writeln("storage-payload-bytes ",
        OverAligned64.sizeof * CandidateStorage.capacity);
    writeln("storage-holder-offset ", StorageHolder.storage.offsetof);

    StorageHolder storageHolder;
    const storageSlotAddress =
        cast(size_t) storageHolder.storage.slotPointer(0);

    writeln("storage-slot-address-mod-element-align ",
        storageSlotAddress % OverAligned64.alignof);
    writeln("storage-slot-sufficient ",
        storageSlotAddress % OverAligned64.alignof == 0 ? 1 : 0);

    assert(storageSlotAddress % OverAligned64.alignof == 0);

    StorageHolder[2] storageHolders;
    foreach (holderIndex, ref holder; storageHolders)
    {
        foreach (slotIndex; 0 .. CandidateStorage.capacity)
        {
            const address =
                cast(size_t) holder.storage.slotPointer(slotIndex);
            writeln("storage-holder-array-", holderIndex,
                "-slot-", slotIndex,
                "-mod-element-align ",
                address % OverAligned64.alignof);
            assert(address % OverAligned64.alignof == 0);
        }
    }

    CandidateStorage[2] storageArray;
    foreach (storageIndex, ref storage; storageArray)
    {
        foreach (slotIndex; 0 .. CandidateStorage.capacity)
        {
            const address = cast(size_t) storage.slotPointer(slotIndex);
            writeln("storage-array-", storageIndex,
                "-slot-", slotIndex,
                "-mod-element-align ",
                address % OverAligned64.alignof);
            assert(address % OverAligned64.alignof == 0);
        }
    }

    writeln("reference-storage-dynamic ",
        ReferenceStorage.usesDynamicAlignment ? 1 : 0);
    writeln("reference-storage-align ", ReferenceStorage.alignof);
    writeln("reference-storage-size ", ReferenceStorage.sizeof);
    writeln("reference-storage-holder-offset ",
        ReferenceStorageHolder.storage.offsetof);

    ReferenceStorageHolder referenceHolder;
    foreach (slotIndex; 0 .. ReferenceStorage.capacity)
    {
        const address =
            cast(size_t) referenceHolder.storage.slotPointer(slotIndex);
        writeln("reference-storage-slot-", slotIndex,
            "-mod-element-align ",
            address % OverAlignedReference64.alignof);
        assert(address % OverAlignedReference64.alignof == 0);
    }

    writeln("normal-storage-dynamic ",
        NormalStorage.usesDynamicAlignment ? 1 : 0);
    writeln("normal-storage-align ", NormalStorage.alignof);
    writeln("normal-storage-size ", NormalStorage.sizeof);

    NormalStorage normalStorage;
    assert(cast(size_t) normalStorage.slotPointer(0) %
        NormalAligned.alignof == 0);
}
