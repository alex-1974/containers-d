/**
 * Research prototype for the bounded single-owner / multi-thief
 * work-stealing deque family.
 *
 * This module is intentionally not re-exported from the package root.
 * Production promotion is tracked by issue #38.
 */
module containers.research.work_stealing_deque;

import containers.internal.element_lifetime : elementNeedsDestruction;
import core.atomic :
    MemoryOrder,
    atomicFence,
    atomicFetchAdd,
    atomicLoad,
    atomicStore,
    cas;

/**
 * Result carrier for owner pop and thief steal.
 *
 * Occupancy is carried by `found`; T.init is never used as an empty
 * sentinel.
 */
struct WorkStealingTakeResult(T)
{
    T value;
    bool found;
}

private enum bool atomicWorkStealingTransport(T) =
    __traits(compiles, {
        void probe() @safe @nogc nothrow
        {
            shared T slot = T.init;
            T value = T.init;

            atomicStore!(MemoryOrder.raw)(slot, value);
            value = atomicLoad!(MemoryOrder.raw)(slot);
        }
    });

/**
 * Whether T satisfies the current production-neighbourhood transport contract.
 *
 * This is deliberately narrower than general D copyability:
 *
 * - value transfer must compile through core.atomic shared storage;
 * - queue slots must not own destructor-driven lifetime;
 * - ownership/reclamation of any referenced object remains external.
 *
 * The predicate is research-visible so positive/negative compile probes can
 * qualify the contract before any public API is frozen.
 */
enum bool isWorkStealingTransportElement(T) =
    !elementNeedsDestruction!T &&
    atomicWorkStealingTransport!T;

/**
 * Sequentially-consistent ordering primitive required by the selected P08e
 * marked-top protocol.
 *
 * P11 in the source research identified this helper as the narrow trusted
 * boundary. It receives only the address of the deque's internal fence word,
 * exposes no pointer, and owns no element lifetime.
 */
private void workStealingSeqCstBarrier(
    scope shared int* fenceWord)
    @trusted @nogc nothrow
{
    version (LDC)
    {
        version (X86_64)
        {
            atomicFetchAdd!(MemoryOrder.seq)(
                *fenceWord,
                0);
            return;
        }
    }

    atomicFence!(MemoryOrder.seq)();
}

/**
 * Research form of the selected bounded marked-top work-stealing deque.
 *
 * Protocol:
 *
 * - exactly one owner may call tryPush/pop;
 * - zero or more thieves may call steal/stealBatch;
 * - the type is bounded and never resizes;
 * - full is reported only by tryPush == false;
 * - the deque transports T values and owns no externally referenced object.
 *
 * Capacity is source-visible as an actual element count rather than the
 * research prototype's LogSize parameter.
 */
struct ResearchWorkStealingDeque(T, size_t Capacity)
if (isWorkStealingTransportElement!T)
{
    static assert(size_t.sizeof == ulong.sizeof,
        "Work-stealing deque research currently requires a 64-bit target");
    static assert(Capacity >= 2,
        "Work-stealing deque capacity must be at least two");
    static assert((Capacity & (Capacity - 1)) == 0,
        "Work-stealing deque capacity must be a power of two");
    static assert(Capacity <= (size_t(1) << 61),
        "Work-stealing deque capacity exceeds the qualified 63-bit counter-domain bound");

    @disable this(this);

    enum size_t capacity = Capacity;
    enum size_t mask = Capacity - 1;

private:
    /*
     * P08e state encoding:
     *
     * bits 63..1 = 63-bit modular logical top
     * bit 0      = batch-in-progress marker
     */
    enum ulong counterMask = ulong.max >> 1;
    enum ulong counterCapacity = cast(ulong) Capacity;
    enum ulong busyBit = 1;

    shared ulong _topState = 0;
    ubyte[56] _topPadding;

    shared ulong _bottom = 0;
    shared int _fenceWord = 0;
    ubyte[52] _bottomPadding;

    shared T[Capacity] _buffer;

    static ulong encodeTop(
        ulong top,
        bool busy)
        @safe @nogc nothrow
    {
        return
            ((top & counterMask) << 1) |
            (busy ? busyBit : 0);
    }

    static ulong decodeTop(
        ulong state)
        @safe @nogc nothrow
    {
        return (state >> 1) & counterMask;
    }

    static bool isBusy(
        ulong state)
        @safe @nogc nothrow
    {
        return (state & busyBit) != 0;
    }

    static ulong increment(
        ulong value)
        @safe @nogc nothrow
    {
        return (value + 1) & counterMask;
    }

    static ulong addCounter(
        ulong value,
        size_t amount)
        @safe @nogc nothrow
    {
        return
            (value + cast(ulong) amount) &
            counterMask;
    }

    static ulong subtract(
        ulong lhs,
        ulong rhs)
        @safe @nogc nothrow
    {
        return (lhs - rhs) & counterMask;
    }

public:
    /**
     * Owner-only insertion.
     *
     * Returns false when the bounded deque is full. No allocation, resize,
     * execution, spill or other policy action occurs.
     */
    bool tryPush(T item)
        @safe @nogc nothrow
    {
        const b =
            atomicLoad!(MemoryOrder.raw)(
                _bottom);

        const state =
            atomicLoad!(MemoryOrder.acq)(
                _topState);

        const t = decodeTop(state);
        const count = subtract(b, t);

        if (count >= counterCapacity)
            return false;

        atomicStore!(MemoryOrder.raw)(
            _buffer[
                cast(size_t)(
                    b &
                    cast(ulong) mask)],
            item);

        atomicFence!(MemoryOrder.rel)();

        atomicStore!(MemoryOrder.rel)(
            _bottom,
            increment(b));

        return true;
    }

    /// Owner-only LIFO removal.
    WorkStealingTakeResult!T pop()
        @safe @nogc nothrow
    {
        for (;;)
        {
            const oldBottom =
                atomicLoad!(MemoryOrder.raw)(
                    _bottom);

            const b =
                (oldBottom - 1) &
                counterMask;

            atomicStore!(MemoryOrder.raw)(
                _bottom,
                b);

            workStealingSeqCstBarrier(
                &_fenceWord);

            const state =
                atomicLoad!(MemoryOrder.raw)(
                    _topState);

            if (isBusy(state))
            {
                atomicStore!(MemoryOrder.raw)(
                    _bottom,
                    oldBottom);
                continue;
            }

            const t = decodeTop(state);
            const distance = subtract(b, t);

            WorkStealingTakeResult!T result;

            if (distance < counterCapacity)
            {
                result.found = true;

                result.value =
                    atomicLoad!(MemoryOrder.raw)(
                        _buffer[
                            cast(size_t)(
                                b &
                                cast(ulong) mask)]);

                if (distance == 0)
                {
                    auto expected = state;

                    const next =
                        encodeTop(
                            increment(t),
                            false);

                    if (!cas!(
                            MemoryOrder.seq,
                            MemoryOrder.raw)(
                                &_topState,
                                expected,
                                next))
                    {
                        result =
                            WorkStealingTakeResult!T.init;
                    }

                    atomicStore!(MemoryOrder.raw)(
                        _bottom,
                        oldBottom);
                }
            }
            else
            {
                atomicStore!(MemoryOrder.raw)(
                    _bottom,
                    oldBottom);
            }

            return result;
        }
    }

    /// Thief-safe single-item FIFO removal from the opposite end.
    WorkStealingTakeResult!T steal()
        @safe @nogc nothrow
    {
        const state =
            atomicLoad!(MemoryOrder.acq)(
                _topState);

        WorkStealingTakeResult!T result;

        if (isBusy(state))
            return result;

        const t = decodeTop(state);

        workStealingSeqCstBarrier(
            &_fenceWord);

        const b =
            atomicLoad!(MemoryOrder.acq)(
                _bottom);

        const count = subtract(b, t);

        if (
            count != 0 &&
            count <= counterCapacity)
        {
            result.value =
                atomicLoad!(MemoryOrder.raw)(
                    _buffer[
                        cast(size_t)(
                            t &
                            cast(ulong) mask)]);

            auto expected = state;

            if (cas!(
                    MemoryOrder.seq,
                    MemoryOrder.raw)(
                        &_topState,
                        expected,
                        encodeTop(
                            increment(t),
                            false)))
            {
                result.found = true;
            }
        }

        return result;
    }

    /**
     * Thief-safe bounded batch steal.
     *
     * Values are written in thief/FIFO order into caller-owned output storage.
     * No allocation or scheduler policy is performed.
     */
    size_t stealBatch(
        scope T[] output)
        @safe @nogc nothrow
    {
        if (output.length == 0)
            return 0;

        const state =
            atomicLoad!(MemoryOrder.acq)(
                _topState);

        if (isBusy(state))
            return 0;

        const t = decodeTop(state);

        auto expected = state;

        const busyState =
            encodeTop(
                t,
                true);

        if (!cas!(
                MemoryOrder.seq,
                MemoryOrder.raw)(
                    &_topState,
                    expected,
                    busyState))
        {
            return 0;
        }

        workStealingSeqCstBarrier(
            &_fenceWord);

        const b =
            atomicLoad!(MemoryOrder.acq)(
                _bottom);

        const available =
            subtract(b, t);

        if (
            available == 0 ||
            available > counterCapacity)
        {
            atomicStore!(MemoryOrder.rel)(
                _topState,
                encodeTop(
                    t,
                    false));

            return 0;
        }

        size_t take =
            cast(size_t) available;

        if (take > output.length)
            take = output.length;

        foreach (i; 0 .. take)
        {
            const index =
                addCounter(
                    t,
                    i);

            output[i] =
                atomicLoad!(MemoryOrder.raw)(
                    _buffer[
                        cast(size_t)(
                            index &
                            cast(ulong) mask)]);
        }

        atomicStore!(MemoryOrder.rel)(
            _topState,
            encodeTop(
                addCounter(
                    t,
                    take),
                false));

        return take;
    }

    version (unittest)
    {
        void researchSetEmptyIndex(
            ulong index)
            @safe @nogc nothrow
        {
            const normalized =
                index &
                counterMask;

            atomicStore!(MemoryOrder.raw)(
                _topState,
                encodeTop(
                    normalized,
                    false));

            atomicStore!(MemoryOrder.raw)(
                _bottom,
                normalized);
        }

        ulong researchTopSnapshot() const
            @safe @nogc nothrow
        {
            return decodeTop(
                atomicLoad!(MemoryOrder.raw)(
                    _topState));
        }

        ulong researchBottomSnapshot() const
            @safe @nogc nothrow
        {
            return
                atomicLoad!(MemoryOrder.raw)(
                    _bottom);
        }
    }
}

version (unittest)
{
    private struct Handle64
    {
        ulong value;
    }

    private struct Pair128
    {
        ulong first;
        ulong second;
    }

    private struct SharedPtrHandle
    {
        shared(void)* ptr;
    }

    private struct DestructorValue
    {
        ulong value;

        ~this() @safe @nogc nothrow {}
    }
}

unittest
{
    static assert(isWorkStealingTransportElement!ulong);
    static assert(isWorkStealingTransportElement!Handle64);
    static assert(isWorkStealingTransportElement!Pair128);
    static assert(isWorkStealingTransportElement!SharedPtrHandle);

    static assert(!isWorkStealingTransportElement!(ulong*));
    static assert(!isWorkStealingTransportElement!Object);
    static assert(!isWorkStealingTransportElement!DestructorValue);

    static assert(!__traits(compiles,
        ResearchWorkStealingDeque!(ulong, 1)));
    static assert(!__traits(compiles,
        ResearchWorkStealingDeque!(ulong, 3)));
}

unittest
{
    ResearchWorkStealingDeque!(ulong, 8) queue;

    static assert(queue.capacity == 8);
    static assert(!__traits(compiles, {
        auto copy = queue;
    }));

    assert(queue.tryPush(10));
    assert(queue.tryPush(20));
    assert(queue.tryPush(30));

    auto owner = queue.pop();
    assert(owner.found);
    assert(owner.value == 30);

    auto thief = queue.steal();
    assert(thief.found);
    assert(thief.value == 10);

    ulong[4] batch;
    const taken = queue.stealBatch(batch[]);

    assert(taken == 1);
    assert(batch[0] == 20);

    assert(!queue.pop().found);
    assert(!queue.steal().found);
}

unittest
{
    ResearchWorkStealingDeque!(ulong, 4) queue;

    foreach (value; 1UL .. 5UL)
        assert(queue.tryPush(value));

    assert(!queue.tryPush(5));

    auto thief = queue.steal();
    assert(thief.found);
    assert(thief.value == 1);

    assert(queue.tryPush(5));

    auto owner = queue.pop();
    assert(owner.found);
    assert(owner.value == 5);
}

unittest
{
    // Exercise modular slot selection near the selected 63-bit counter wrap.
    ResearchWorkStealingDeque!(ulong, 8) queue;

    enum ulong nearWrap =
        (ulong.max >> 1) - 3;

    queue.researchSetEmptyIndex(
        nearWrap);

    assert(queue.tryPush(41));
    assert(queue.tryPush(42));
    assert(queue.tryPush(43));
    assert(queue.tryPush(44));

    auto first = queue.steal();
    assert(first.found);
    assert(first.value == 41);

    auto last = queue.pop();
    assert(last.found);
    assert(last.value == 44);
}
