module containers.blocking_queue_contention_parity_probe;

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
                _notEmpty.wait();

            if (_length == 0)
                return BlockingQueuePopResult!ulong(
                    BlockingQueuePopStatus.closed,
                    ulong.init);

            const value = _storage[_head];

            --_length;
            if (_length == 0)
            {
                _head = 0;
            }
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
}

private void pinCurrentThread(size_t cpu)
{
    version (linux)
    {
        cpu_set_t mask = cpu_set_t.init;
        CPU_SET(cpu, &mask);

        if (sched_setaffinity(
                0,
                cpu_set_t.sizeof,
                &mask) != 0)
        {
            throw new Exception(
                "sched_setaffinity failed");
        }

        const actual = sched_getcpu();

        if (
            actual < 0 ||
            cast(size_t)actual != cpu)
        {
            throw new Exception(
                "affinity verification failed");
        }
    }
    else
    {
        throw new Exception(
            "Linux affinity required");
    }
}

private ulong xorZeroTo(ulong inclusive)
    @safe @nogc nothrow
{
    final switch (inclusive & 3UL)
    {
        case 0: return inclusive;
        case 1: return 1;
        case 2: return inclusive + 1;
        case 3: return 0;
    }
}

private double runTransfer(Q)(
    size_t producerCount,
    size_t consumerCount,
    size_t capacity,
    size_t total)
{
    if (
        producerCount == 0 ||
        consumerCount == 0 ||
        producerCount + consumerCount > 4 ||
        capacity == 0 ||
        total == 0 ||
        total % producerCount != 0)
    {
        throw new Exception(
            "invalid contention topology");
    }

    auto queue = new Q(capacity);

    shared ulong ready;
    shared bool start;

    auto producers = new Thread[](producerCount);
    auto consumers = new Thread[](consumerCount);

    auto counts = new ulong[](consumerCount);
    auto sums = new ulong[](consumerCount);
    auto xors = new ulong[](consumerCount);

    const perProducer = total / producerCount;

    Thread makeProducer(size_t producerIndex)
    {
        return new Thread({
            pinCurrentThread(producerIndex);

            atomicFetchAdd!(MemoryOrder.seq)(
                ready,
                1UL);

            while (!atomicLoad!(MemoryOrder.acq)(start))
            {
            }

            const base =
                cast(ulong)producerIndex *
                cast(ulong)perProducer;

            foreach (i; 0 .. perProducer)
            {
                const value =
                    base + cast(ulong)i;

                for (;;)
                {
                    final switch (queue.tryPush(value))
                    {
                        case BlockingQueuePushResult.pushed:
                            break;

                        case BlockingQueuePushResult.full:
                            Thread.yield();
                            continue;

                        case BlockingQueuePushResult.closed:
                            throw new Exception(
                                "producer observed unexpected close");
                    }

                    break;
                }
            }
        });
    }

    Thread makeConsumer(size_t consumerIndex)
    {
        return new Thread({
            pinCurrentThread(
                producerCount + consumerIndex);

            atomicFetchAdd!(MemoryOrder.seq)(
                ready,
                1UL);

            while (!atomicLoad!(MemoryOrder.acq)(start))
            {
            }

            ulong localCount;
            ulong localSum;
            ulong localXor;

            for (;;)
            {
                auto result = queue.waitPop();

                if (
                    result.status ==
                    BlockingQueuePopStatus.closed)
                {
                    break;
                }

                ++localCount;
                localSum += result.value;
                localXor ^= result.value;
            }

            counts[consumerIndex] = localCount;
            sums[consumerIndex] = localSum;
            xors[consumerIndex] = localXor;
        });
    }

    foreach (i; 0 .. consumerCount)
    {
        consumers[i] = makeConsumer(i);
        consumers[i].start();
    }

    foreach (i; 0 .. producerCount)
    {
        producers[i] = makeProducer(i);
        producers[i].start();
    }

    const expectedReady =
        cast(ulong)(producerCount + consumerCount);

    while (
        atomicLoad!(MemoryOrder.acq)(ready) !=
        expectedReady)
    {
        Thread.yield();
    }

    const before = MonoTime.currTime;

    atomicStore!(MemoryOrder.rel)(
        start,
        true);

    foreach (producer; producers)
        producer.join();

    queue.close();

    foreach (consumer; consumers)
        consumer.join();

    const after = MonoTime.currTime;

    ulong observedCount;
    ulong observedSum;
    ulong observedXor;

    foreach (i; 0 .. consumerCount)
    {
        observedCount += counts[i];
        observedSum += sums[i];
        observedXor ^= xors[i];
    }

    const expectedSum =
        cast(ulong)(
            (cast(ulong)total *
             (cast(ulong)total - 1UL)) /
            2UL);

    const expectedXor =
        xorZeroTo(cast(ulong)total - 1UL);

    if (
        observedCount != total ||
        observedSum != expectedSum ||
        observedXor != expectedXor)
    {
        throw new Exception(
            "contention accounting mismatch");
    }

    const nanos =
        (after - before).total!"nsecs";

    return
        cast(double)nanos /
        cast(double)total;
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

private void compare(
    size_t producerCount,
    size_t consumerCount,
    size_t capacity,
    size_t total,
    size_t warmups,
    size_t samples)
{
    foreach (_; 0 .. warmups)
    {
        runTransfer!(ResearchBlockingQueue!ulong)(
            producerCount,
            consumerCount,
            capacity,
            total);

        runTransfer!ManualBlockingQueue(
            producerCount,
            consumerCount,
            capacity,
            total);
    }

    auto candidate = new double[](samples);
    auto manual = new double[](samples);
    auto pairedRatios = new double[](samples);

    foreach (sample; 0 .. samples)
    {
        if ((sample & 1) == 0)
        {
            candidate[sample] =
                runTransfer!(ResearchBlockingQueue!ulong)(
                    producerCount,
                    consumerCount,
                    capacity,
                    total);

            manual[sample] =
                runTransfer!ManualBlockingQueue(
                    producerCount,
                    consumerCount,
                    capacity,
                    total);
        }
        else
        {
            manual[sample] =
                runTransfer!ManualBlockingQueue(
                    producerCount,
                    consumerCount,
                    capacity,
                    total);

            candidate[sample] =
                runTransfer!(ResearchBlockingQueue!ulong)(
                    producerCount,
                    consumerCount,
                    capacity,
                    total);
        }

        pairedRatios[sample] =
            candidate[sample] /
            manual[sample];
    }

    const candidateMedian =
        median(candidate.dup);
    const manualMedian =
        median(manual.dup);
    const ratioMedian =
        median(pairedRatios.dup);

    writeln(
        "capacity=", capacity,
        " producers=", producerCount,
        " consumers=", consumerCount,
        " candidate_ns=", candidateMedian,
        " manual_ns=", manualMedian,
        " ratio=", ratioMedian);
}

void main()
{
    enum size_t total = 65_536;
    enum size_t warmups = 1;
    enum size_t samples = 6;
    enum size_t[3] capacities = [1, 16, 256];

    foreach (capacity; capacities)
    {
        compare(1, 1, capacity, total, warmups, samples);
        compare(2, 1, capacity, total, warmups, samples);
        compare(1, 2, capacity, total, warmups, samples);
        compare(2, 2, capacity, total, warmups, samples);
    }
}
