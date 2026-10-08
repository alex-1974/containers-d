module containers.blocking_queue_sync_cost_probe;

import containers.research.blocking_queue :
    BlockingQueuePopResult,
    BlockingQueuePopStatus,
    BlockingQueuePushResult,
    ResearchBlockingQueue;
import core.atomic :
    MemoryOrder,
    atomicFetchAdd,
    atomicLoad,
    atomicStore;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.time : MonoTime;
version (linux)
{
    import core.sys.linux.sched :
        CPU_SET,
        cpu_set_t,
        sched_getcpu,
        sched_setaffinity;
}
import std.algorithm : sort;
import std.stdio : writeln;

private final class ManualBlockingQueue
{
private:
    Mutex _mutex;
    Condition _notEmpty;
    ulong[] _storage;
    size_t _head;
    size_t _length;
    bool _closed;
    size_t _waitingConsumers;

public:
    this(size_t capacity)
    {
        _mutex = new Mutex;
        _notEmpty = new Condition(_mutex);
        _storage = new ulong[](capacity);
    }

    BlockingQueuePushResult tryPush(ulong value)
    {
        synchronized (_mutex)
        {
            if (_closed)
                return BlockingQueuePushResult.closed;
            if (_length == _storage.length)
                return BlockingQueuePushResult.full;

            const tailRoom = _storage.length - _head;
            const physical =
                _length < tailRoom
                    ? _head + _length
                    : _length - tailRoom;

            _storage[physical] = value;
            ++_length;
            _notEmpty.notify();
            return BlockingQueuePushResult.pushed;
        }
    }

    BlockingQueuePopResult!ulong waitPop()
    {
        synchronized (_mutex)
        {
            while (_length == 0 && !_closed)
            {
                ++_waitingConsumers;
                scope(exit) --_waitingConsumers;
                _notEmpty.wait();
            }

            if (_length == 0)
                return BlockingQueuePopResult!ulong(
                    BlockingQueuePopStatus.closed,
                    ulong.init);

            const value = _storage[_head];
            --_length;

            if (_length == 0)
                _head = 0;
            else
            {
                ++_head;
                if (_head == _storage.length)
                    _head = 0;
            }

            return BlockingQueuePopResult!ulong(
                BlockingQueuePopStatus.value,
                value);
        }
    }

    bool close()
    {
        synchronized (_mutex)
        {
            if (_closed)
                return false;
            _closed = true;
            _notEmpty.notifyAll();
            return true;
        }
    }

    size_t researchWaitingConsumers()
    {
        synchronized (_mutex)
            return _waitingConsumers;
    }
}

private void pinCurrentThread(size_t cpu)
{
    version (linux)
    {
        cpu_set_t mask = cpu_set_t.init;
        CPU_SET(cpu, &mask);

        if (sched_setaffinity(0, cpu_set_t.sizeof, &mask) != 0)
            throw new Exception("sched_setaffinity failed");

        const actual = sched_getcpu();
        if (actual < 0 || cast(size_t)actual != cpu)
            throw new Exception("affinity verification failed");
    }
    else
        throw new Exception("Linux affinity required");
}

private double median(double[] values)
{
    sort(values);
    if ((values.length & 1) != 0)
        return values[values.length / 2];

    return
        (values[values.length / 2 - 1] +
         values[values.length / 2]) /
        2.0;
}

private double runUncontended(Q)(size_t rounds)
{
    auto queue = new Q(256);
    ulong checksum;

    const before = MonoTime.currTime;

    foreach (i; 0 .. rounds)
    {
        const value = cast(ulong)i;
        if (queue.tryPush(value) != BlockingQueuePushResult.pushed)
            throw new Exception("unexpected uncontended push result");

        const result = queue.waitPop();
        if (result.status != BlockingQueuePopStatus.value)
            throw new Exception("unexpected uncontended pop result");

        checksum += result.value;
    }

    const after = MonoTime.currTime;

    const expected =
        (cast(ulong)rounds * (cast(ulong)rounds - 1UL)) / 2UL;
    if (checksum != expected)
        throw new Exception("uncontended checksum mismatch");

    return
        cast(double)(after - before).total!"nsecs" /
        cast(double)(rounds * 2);
}

private double runWakeRoundTrip(Q)(size_t rounds)
{
    auto queue = new Q(1);

    shared ulong ready;
    shared ulong consumed;
    shared bool start;

    auto consumer = new Thread({
        pinCurrentThread(1);
        atomicStore!(MemoryOrder.rel)(ready, 1UL);

        while (!atomicLoad!(MemoryOrder.acq)(start))
        {
        }

        foreach (i; 0 .. rounds)
        {
            const result = queue.waitPop();
            if (
                result.status != BlockingQueuePopStatus.value ||
                result.value != cast(ulong)i)
            {
                throw new Exception("wake round-trip value mismatch");
            }

            atomicStore!(MemoryOrder.rel)(
                consumed,
                cast(ulong)i + 1UL);
        }
    });

    consumer.start();
    pinCurrentThread(0);

    while (atomicLoad!(MemoryOrder.acq)(ready) != 1UL)
        Thread.yield();

    const before = MonoTime.currTime;
    atomicStore!(MemoryOrder.rel)(start, true);

    foreach (i; 0 .. rounds)
    {
        for (;;)
        {
            final switch (queue.tryPush(cast(ulong)i))
            {
                case BlockingQueuePushResult.pushed:
                    break;
                case BlockingQueuePushResult.full:
                    Thread.yield();
                    continue;
                case BlockingQueuePushResult.closed:
                    throw new Exception("unexpected close");
            }
            break;
        }

        while (
            atomicLoad!(MemoryOrder.acq)(consumed) !=
            cast(ulong)i + 1UL)
        {
        }
    }

    const after = MonoTime.currTime;
    consumer.join();

    return
        cast(double)(after - before).total!"nsecs" /
        cast(double)rounds;
}

private double runCloseWakeAll(Q)(size_t waiterCount)
{
    if (waiterCount == 0 || waiterCount > 3)
        throw new Exception("invalid waiter count");

    auto queue = new Q(1);
    shared ulong finished;
    auto consumers = new Thread[](waiterCount);

    pinCurrentThread(0);

    foreach (i; 0 .. waiterCount)
    {
        consumers[i] = new Thread({
            pinCurrentThread(i + 1);

            const result = queue.waitPop();
            if (result.status != BlockingQueuePopStatus.closed)
                throw new Exception("close wake returned value");

            atomicFetchAdd!(MemoryOrder.seq)(finished, 1UL);
        });

        consumers[i].start();
    }

    while (queue.researchWaitingConsumers() != waiterCount)
        Thread.yield();

    const before = MonoTime.currTime;

    if (!queue.close())
        throw new Exception("first close did not transition");

    while (
        atomicLoad!(MemoryOrder.acq)(finished) !=
        cast(ulong)waiterCount)
    {
    }

    const after = MonoTime.currTime;

    foreach (consumer; consumers)
        consumer.join();

    if (queue.close())
        throw new Exception("second close unexpectedly transitioned");

    return cast(double)(after - before).total!"nsecs";
}

private void compareCloseWakeAll(
    size_t waiterCount,
    size_t warmups,
    size_t samples)
{
    foreach (_; 0 .. warmups)
    {
        runCloseWakeAll!(ResearchBlockingQueue!ulong)(waiterCount);
        runCloseWakeAll!ManualBlockingQueue(waiterCount);
    }

    auto candidate = new double[](samples);
    auto manual = new double[](samples);
    auto ratios = new double[](samples);

    foreach (sample; 0 .. samples)
    {
        if ((sample & 1) == 0)
        {
            candidate[sample] =
                runCloseWakeAll!(ResearchBlockingQueue!ulong)(waiterCount);
            manual[sample] =
                runCloseWakeAll!ManualBlockingQueue(waiterCount);
        }
        else
        {
            manual[sample] =
                runCloseWakeAll!ManualBlockingQueue(waiterCount);
            candidate[sample] =
                runCloseWakeAll!(ResearchBlockingQueue!ulong)(waiterCount);
        }

        ratios[sample] = candidate[sample] / manual[sample];
    }

    writeln(
        "mode=close-wake-all",
        " waiters=", waiterCount,
        " candidate_ns=", median(candidate.dup),
        " manual_ns=", median(manual.dup),
        " ratio=", median(ratios.dup));
}

private void compareUncontended(
    size_t rounds,
    size_t warmups,
    size_t samples)
{
    foreach (_; 0 .. warmups)
    {
        runUncontended!(ResearchBlockingQueue!ulong)(rounds);
        runUncontended!ManualBlockingQueue(rounds);
    }

    auto candidate = new double[](samples);
    auto manual = new double[](samples);
    auto ratios = new double[](samples);

    foreach (sample; 0 .. samples)
    {
        if ((sample & 1) == 0)
        {
            candidate[sample] =
                runUncontended!(ResearchBlockingQueue!ulong)(rounds);
            manual[sample] =
                runUncontended!ManualBlockingQueue(rounds);
        }
        else
        {
            manual[sample] =
                runUncontended!ManualBlockingQueue(rounds);
            candidate[sample] =
                runUncontended!(ResearchBlockingQueue!ulong)(rounds);
        }

        ratios[sample] = candidate[sample] / manual[sample];
    }

    writeln(
        "mode=uncontended",
        " candidate_ns_per_op=", median(candidate.dup),
        " manual_ns_per_op=", median(manual.dup),
        " ratio=", median(ratios.dup));
}

private void compareWake(
    size_t rounds,
    size_t warmups,
    size_t samples)
{
    foreach (_; 0 .. warmups)
    {
        runWakeRoundTrip!(ResearchBlockingQueue!ulong)(rounds);
        runWakeRoundTrip!ManualBlockingQueue(rounds);
    }

    auto candidate = new double[](samples);
    auto manual = new double[](samples);
    auto ratios = new double[](samples);

    foreach (sample; 0 .. samples)
    {
        if ((sample & 1) == 0)
        {
            candidate[sample] =
                runWakeRoundTrip!(ResearchBlockingQueue!ulong)(rounds);
            manual[sample] =
                runWakeRoundTrip!ManualBlockingQueue(rounds);
        }
        else
        {
            manual[sample] =
                runWakeRoundTrip!ManualBlockingQueue(rounds);
            candidate[sample] =
                runWakeRoundTrip!(ResearchBlockingQueue!ulong)(rounds);
        }

        ratios[sample] = candidate[sample] / manual[sample];
    }

    writeln(
        "mode=wait-wake-roundtrip",
        " candidate_ns=", median(candidate.dup),
        " manual_ns=", median(manual.dup),
        " ratio=", median(ratios.dup));
}

void main()
{
    compareUncontended(1_000_000, 2, 8);
    compareWake(16_384, 1, 6);

    foreach (waiterCount; [1, 2, 3])
        compareCloseWakeAll(waiterCount, 2, 8);
}
