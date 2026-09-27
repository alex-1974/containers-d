/**
 * Structural contract probes for raw T-slot storage used by container-family
 * research.
 *
 * Raw-slot storage provides addresses and contiguous spans only. It does not
 * decide which slots contain live T objects, nor does this contract prescribe
 * how storage is acquired or released.
 */
module containers.internal.storage_contract;

/**
 * Whether S exposes the minimal slot-access surface required by family
 * algorithms for element storage.
 *
 * This is intentionally narrower than an allocator contract. Inline storage
 * and runtime-owned storage can both satisfy it.
 *
 * Semantic obligations not mechanically provable here:
 * - every slot address is suitably aligned for T;
 * - distinct physical slots do not overlap;
 * - storage remains valid for the documented owner lifetime;
 * - mutable/const slices describe exactly the requested physical slots.
 */
package(containers) enum bool isRawSlotStorage(S, T) =
    __traits(compiles, {
        void probe(
            ref S storage,
            ref const(S) constStorage) @safe @nogc nothrow
        {
            size_t cap = storage.capacity;

            if (cap != 0)
            {
                T* mutableSlot = storage.slotPointer(0);
                const(T)* constSlot = constStorage.slotPointer(0);

                T[] mutableSpan = storage.slotSlice(0, 1);
                const(T)[] constSpan = constStorage.slotSlice(0, 1);

                assert(mutableSlot !is null);
                assert(constSlot !is null);
                assert(mutableSpan.length == 1);
                assert(constSpan.length == 1);
            }
        }
    });


/**
 * Whether raw slot storage can sanitize one slot after the T lifetime in that
 * slot has ended.
 *
 * The operation is storage-owned because its purpose depends on how the backing
 * memory participates in GC scanning. For T without indirections it may compile
 * to a no-op.
 */
package(containers) enum bool hasVacatedSlotCleanup(S) =
    __traits(compiles, {
        void probe(ref S storage) @safe @nogc nothrow
        {
            if (storage.capacity != 0)
                storage.clearVacatedSlot(0);
        }
    });

/**
 * Raw slot storage suitable for repeated construct/destroy/reuse cycles.
 *
 * This refines the borrowing contract with storage-specific cleanup of slots
 * whose element lifetime has already ended.
 */
package(containers) enum bool isReusableRawSlotStorage(S, T) =
    isRawSlotStorage!(S, T) &&
    hasVacatedSlotCleanup!S;

version (unittest)
{
    import containers.internal.runtime_storage : RuntimeStorageOwner;

    private struct InlineRawSlots(T, size_t Capacity)
    {
        static assert(Capacity > 0);

        align(T.alignof) ubyte[T.sizeof * Capacity] _bytes = void;

        enum size_t capacity = Capacity;

        T* slotPointer(size_t physicalIndex)
            return scope @safe @nogc nothrow
        {
            assert(physicalIndex < Capacity);

            return (() @trusted =>
                cast(T*) (_bytes.ptr + physicalIndex * T.sizeof))();
        }

        const(T)* slotPointer(size_t physicalIndex)
            const return scope @safe @nogc nothrow
        {
            assert(physicalIndex < Capacity);

            return (() @trusted =>
                cast(const(T)*) (_bytes.ptr + physicalIndex * T.sizeof))();
        }

        T[] slotSlice(size_t physicalStart, size_t count)
            return scope @safe @nogc nothrow
        {
            if (count == 0)
                return null;

            assert(physicalStart < Capacity);
            assert(count <= Capacity - physicalStart);

            return (() @trusted =>
                slotPointer(physicalStart)[0 .. count])();
        }

        const(T)[] slotSlice(size_t physicalStart, size_t count)
            const return scope @safe @nogc nothrow
        {
            if (count == 0)
                return null;

            assert(physicalStart < Capacity);
            assert(count <= Capacity - physicalStart);

            return (() @trusted =>
                slotPointer(physicalStart)[0 .. count])();
        }


        void clearVacatedSlot(size_t physicalIndex)
            @safe @nogc nothrow
        {
            assert(physicalIndex < Capacity);
            // Test storage uses int in the positive concept probe, so no GC
            // sanitation is required. Real indirection-bearing storage owns
            // the corresponding byte-clearing rule.
        }
    }

    private struct MissingCleanup
    {
        enum size_t capacity = 1;

        int* slotPointer(size_t) @safe @nogc nothrow
        {
            return null;
        }

        const(int)* slotPointer(size_t) const @safe @nogc nothrow
        {
            return null;
        }

        int[] slotSlice(size_t, size_t) @safe @nogc nothrow
        {
            return null;
        }

        const(int)[] slotSlice(size_t, size_t) const @safe @nogc nothrow
        {
            return null;
        }
    }

    private struct MissingConstAccess
    {
        enum size_t capacity = 1;

        int* slotPointer(size_t) @safe @nogc nothrow
        {
            return null;
        }

        int[] slotSlice(size_t, size_t) @safe @nogc nothrow
        {
            return null;
        }
    }
}

unittest
{
    static assert(isRawSlotStorage!(InlineRawSlots!(int, 4), int));
    static assert(isRawSlotStorage!(RuntimeStorageOwner!int, int));

    static assert(isReusableRawSlotStorage!(
        InlineRawSlots!(int, 4), int));
    static assert(isReusableRawSlotStorage!(
        RuntimeStorageOwner!int, int));

    // The base concept deliberately requires both mutable and const borrowing.
    static assert(!isRawSlotStorage!(MissingConstAccess, int));

    // Reusable storage additionally owns post-lifetime slot sanitation.
    static assert(isRawSlotStorage!(MissingCleanup, int));
    static assert(!isReusableRawSlotStorage!(MissingCleanup, int));
}
