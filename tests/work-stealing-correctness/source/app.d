module app;

import containers.work_stealing_deque :
    WorkStealingDeque;

import core.atomic :
    MemoryOrder,
    atomicFetchAdd,
    atomicLoad,
    atomicStore;
import core.thread : Thread;

enum size_t lastItemIterations = 20_000;
enum size_t multiThiefItems = 4_096;
enum size_t multiThiefCount = 4;

private shared ulong persistentRecord;

private struct SharedPtrHandle
{
    shared(ulong)* ptr;
}

private void safeSurfaceProbe()
    @safe @nogc nothrow
{
    static assert(__traits(compiles,
        WorkStealingDeque!(SharedPtrHandle, 4)));

    WorkStealingDeque!(
        SharedPtrHandle,
        4) queue;

    auto value =
        SharedPtrHandle(
            &persistentRecord);

    assert(queue.tryPush(value));

    auto result = queue.pop();
    assert(result.found);
    assert(result.value.ptr is &persistentRecord);

    assert(queue.tryPush(value));

    SharedPtrHandle[2] output;
    const taken =
        queue.stealBatch(output[]);

    assert(taken == 1);
    assert(output[0].ptr is &persistentRecord);
}

private void lastItemRace()
{
    auto queue =
        new WorkStealingDeque!(
            ulong,
            2);

    shared ulong phase;
    shared ulong thiefFound;
    shared ulong thiefValue;

    auto thief =
        new Thread({
            foreach (iteration;
                     0 .. lastItemIterations)
            {
                const request =
                    cast(ulong)(
                        iteration * 2 + 1);

                while (
                    atomicLoad!(
                        MemoryOrder.acq)(
                            phase) !=
                    request)
                {
                }

                const result =
                    queue.steal();

                atomicStore!(
                    MemoryOrder.raw)(
                        thiefValue,
                        result.value);

                atomicStore!(
                    MemoryOrder.raw)(
                        thiefFound,
                        result.found ? 1UL : 0UL);

                atomicStore!(
                    MemoryOrder.rel)(
                        phase,
                        request + 1);
            }
        });

    thief.start();

    size_t ownerWins;
    size_t thiefWins;

    foreach (iteration;
             0 .. lastItemIterations)
    {
        const value =
            cast(ulong)(
                iteration + 1);

        assert(queue.tryPush(value));

        const request =
            cast(ulong)(
                iteration * 2 + 1);

        atomicStore!(
            MemoryOrder.rel)(
                phase,
                request);

        const owner =
            queue.pop();

        while (
            atomicLoad!(
                MemoryOrder.acq)(
                    phase) !=
            request + 1)
        {
        }

        const thiefDidFind =
            atomicLoad!(
                MemoryOrder.raw)(
                    thiefFound) != 0;

        const thiefObserved =
            atomicLoad!(
                MemoryOrder.raw)(
                    thiefValue);

        assert(
            owner.found !=
            thiefDidFind);

        if (owner.found)
        {
            ++ownerWins;
            assert(owner.value == value);
        }
        else
        {
            ++thiefWins;
            assert(thiefObserved == value);
        }
    }

    thief.join();

    assert(
        ownerWins + thiefWins ==
        lastItemIterations);

    assert(!queue.pop().found);
    assert(!queue.steal().found);
}

version (ContainersWorkStealingTestHooks)
{
    private void markedTopOwnerBatchOverlap()
    {
        auto queue =
            new WorkStealingDeque!(
                ulong,
                8);

        foreach (value; 1UL .. 9UL)
            assert(queue.tryPush(value));

        queue.testEnableBatchPause();

        ulong[4] stolen;
        shared size_t taken;

        auto thief =
            new Thread({
                const count =
                    queue.stealBatch(stolen[]);
                atomicStore!(MemoryOrder.rel)(
                    taken,
                    count);
            });

        thief.start();

        while (!queue.testBatchMarkedSnapshot())
        {
        }

        auto releaser =
            new Thread({
                while (
                    queue.testOwnerBusyRetriesSnapshot() ==
                    0)
                {
                }

                queue.testReleaseBatchPause();
            });

        releaser.start();

        const owner =
            queue.pop();

        releaser.join();
        thief.join();

        assert(
            queue.testOwnerBusyRetriesSnapshot() >
            0);

        assert(
            atomicLoad!(MemoryOrder.acq)(
                taken) ==
            4);

        assert(stolen[0] == 1);
        assert(stolen[1] == 2);
        assert(stolen[2] == 3);
        assert(stolen[3] == 4);

        assert(owner.found);
        assert(owner.value == 8);

        auto next = queue.steal();
        assert(next.found);
        assert(next.value == 5);
    }
}

private void nearCapacityConcurrentRefill()
{
    enum size_t capacity = 256;
    enum size_t total = 50_000;

    auto queue =
        new WorkStealingDeque!(
            ulong,
            capacity);

    shared uint[total] seen;
    shared ulong consumed;

    foreach (value; 1UL .. cast(ulong) capacity + 1)
        assert(queue.tryPush(value));

    auto thief =
        new Thread({
            size_t emptySpins;

            while (
                atomicLoad!(
                    MemoryOrder.acq)(
                        consumed) <
                total)
            {
                const result =
                    queue.steal();

                if (!result.found)
                {
                    ++emptySpins;

                    if (
                        emptySpins >
                        20_000_000)
                    {
                        break;
                    }

                    continue;
                }

                emptySpins = 0;

                assert(
                    result.value >= 1 &&
                    result.value <= total);

                const index =
                    cast(size_t)(
                        result.value - 1);

                const prior =
                    atomicFetchAdd!(
                        MemoryOrder.seq)(
                            seen[index],
                            1u);

                assert(prior == 0);

                atomicFetchAdd!(
                    MemoryOrder.seq)(
                        consumed,
                        1UL);
            }
        });

    thief.start();

    foreach (value;
             cast(ulong) capacity + 1 ..
             cast(ulong) total + 1)
    {
        size_t fullSpins;

        while (!queue.tryPush(value))
        {
            ++fullSpins;
            assert(fullSpins < 20_000_000);
        }
    }

    thief.join();

    assert(
        atomicLoad!(
            MemoryOrder.acq)(
                consumed) ==
        total);

    foreach (ref count; seen)
    {
        assert(
            atomicLoad!(
                MemoryOrder.raw)(
                    count) ==
            1);
    }

    assert(!queue.steal().found);
    assert(!queue.pop().found);
}

private void multiThiefExactAccounting()
{
    auto queue =
        new WorkStealingDeque!(
            ulong,
            multiThiefItems);

    foreach (index;
             0 .. multiThiefItems)
    {
        assert(queue.tryPush(
            cast(ulong)(
                index + 1)));
    }

    shared uint[multiThiefItems] seen;
    shared ulong consumed;

    Thread[multiThiefCount] thieves;

    foreach (ref thief; thieves)
    {
        thief =
            new Thread({
                size_t emptySpins;

                while (
                    atomicLoad!(
                        MemoryOrder.acq)(
                            consumed) <
                    multiThiefItems)
                {
                    const result =
                        queue.steal();

                    if (!result.found)
                    {
                        ++emptySpins;

                        if (
                            emptySpins >
                            5_000_000)
                        {
                            break;
                        }

                        continue;
                    }

                    emptySpins = 0;

                    assert(
                        result.value >= 1 &&
                        result.value <=
                            multiThiefItems);

                    const index =
                        cast(size_t)(
                            result.value - 1);

                    const prior =
                        atomicFetchAdd!(
                            MemoryOrder.seq)(
                                seen[index],
                                1u);

                    assert(prior == 0);

                    atomicFetchAdd!(
                        MemoryOrder.seq)(
                            consumed,
                            1UL);
                }
            });

        thief.start();
    }

    foreach (ref thief; thieves)
        thief.join();

    assert(
        atomicLoad!(
            MemoryOrder.acq)(
                consumed) ==
        multiThiefItems);

    foreach (ref count; seen)
    {
        assert(
            atomicLoad!(
                MemoryOrder.raw)(
                    count) ==
            1);
    }

    assert(!queue.steal().found);
    assert(!queue.pop().found);
}

void main()
{
    safeSurfaceProbe();
    lastItemRace();
    multiThiefExactAccounting();
    nearCapacityConcurrentRefill();

    version (ContainersWorkStealingTestHooks)
        markedTopOwnerBatchOverlap();
}
