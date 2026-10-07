module containers.work_stealing_contention_parity_probe;

import containers.research.work_stealing_deque :
    ResearchWorkStealingDeque;
import concurrency.research.modular_bounded_wsq_batch_marked_top :
    MarkedTopBatchBoundedWorkStealingDeque;

import core.atomic :
    MemoryOrder,
    atomicFetchAdd,
    atomicLoad,
    atomicStore;
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
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t logSize = 10;
enum size_t capacity = size_t(1) << logSize;
enum size_t batchWidth = 8;

alias Candidate = ResearchWorkStealingDeque!(ulong, capacity);
alias Reference = MarkedTopBatchBoundedWorkStealingDeque!(ulong, logSize);

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
            cast(size_t) actual != cpu)
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

private ulong xorOneTo(ulong n)
    @safe @nogc nothrow
{
    final switch (n & 3UL)
    {
        case 0: return n;
        case 1: return 1;
        case 2: return n + 1;
        case 3: return 0;
    }
}

private double runTransfer(Q)(
    size_t thiefCount,
    bool batch,
    size_t total)
{
    assert(thiefCount > 0);
    assert(thiefCount <= 3);
    assert(total > capacity);

    pinCurrentThread(0);

    auto queue = new Q;

    shared bool start;
    shared ulong consumed;

    auto threads = new Thread[](thiefCount);
    auto counts = new ulong[](thiefCount);
    auto sums = new ulong[](thiefCount);
    auto xors = new ulong[](thiefCount);

    foreach (index; 0 .. thiefCount)
    {
        threads[index] =
            new Thread({
                pinCurrentThread(index + 1);

                while (!atomicLoad!(MemoryOrder.acq)(start))
                {
                }

                ulong localCount;
                ulong localSum;
                ulong localXor;
                ulong[batchWidth] output;

                for (;;)
                {
                    if (atomicLoad!(MemoryOrder.acq)(consumed) >= total)
                        break;

                    if (batch)
                    {
                        const taken = queue.stealBatch(output[]);

                        if (taken == 0)
                            continue;

                        foreach (i; 0 .. taken)
                        {
                            const value = output[i];
                            localSum += value;
                            localXor ^= value;
                        }

                        localCount += taken;

                        atomicFetchAdd!(MemoryOrder.seq)(
                            consumed,
                            cast(ulong) taken);
                    }
                    else
                    {
                        const result = queue.steal();

                        if (!result.found)
                            continue;

                        ++localCount;
                        localSum += result.value;
                        localXor ^= result.value;

                        atomicFetchAdd!(MemoryOrder.seq)(
                            consumed,
                            1UL);
                    }
                }

                counts[index] = localCount;
                sums[index] = localSum;
                xors[index] = localXor;
            });

        threads[index].start();
    }

    const before = MonoTime.currTime;

    atomicStore!(MemoryOrder.rel)(
        start,
        true);

    foreach (value; 1UL .. cast(ulong) total + 1)
    {
        while (!queue.tryPush(value))
        {
        }
    }

    foreach (thread; threads)
        thread.join();

    const after = MonoTime.currTime;

    ulong count;
    ulong sum;
    ulong xor;

    foreach (index; 0 .. thiefCount)
    {
        count += counts[index];
        sum += sums[index];
        xor ^= xors[index];
    }

    assert(count == total);
    assert(
        atomicLoad!(MemoryOrder.acq)(consumed) ==
        total);

    const expectedSum =
        cast(ulong)(
            (cast(ulong) total *
             (cast(ulong) total + 1UL)) /
            2UL);

    assert(sum == expectedSum);
    assert(xor == xorOneTo(cast(ulong) total));

    assert(!queue.steal().found);
    assert(!queue.pop().found);

    const nanos =
        (after - before).total!"nsecs";

    return
        cast(double) nanos /
        cast(double) total;
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
    size_t thiefCount,
    bool batch,
    size_t total,
    size_t warmups,
    size_t samples)
{
    foreach (_; 0 .. warmups)
    {
        runTransfer!Candidate(thiefCount, batch, total);
        runTransfer!Reference(thiefCount, batch, total);
    }

    assert((samples & 1) == 0);

    auto candidate = new double[](samples);
    auto reference = new double[](samples);
    auto pairedRatios = new double[](samples);
    auto candidateFirstRatios =
        new double[](samples / 2);
    auto referenceFirstRatios =
        new double[](samples / 2);

    size_t candidateFirstIndex;
    size_t referenceFirstIndex;

    foreach (sample; 0 .. samples)
    {
        if ((sample & 1) == 0)
        {
            candidate[sample] =
                runTransfer!Candidate(
                    thiefCount, batch, total);
            reference[sample] =
                runTransfer!Reference(
                    thiefCount, batch, total);
        }
        else
        {
            reference[sample] =
                runTransfer!Reference(
                    thiefCount, batch, total);
            candidate[sample] =
                runTransfer!Candidate(
                    thiefCount, batch, total);
        }

        const ratio =
            candidate[sample] /
            reference[sample];

        pairedRatios[sample] = ratio;

        if ((sample & 1) == 0)
            candidateFirstRatios[
                candidateFirstIndex++] = ratio;
        else
            referenceFirstRatios[
                referenceFirstIndex++] = ratio;
    }

    const candidateMedian =
        median(candidate);
    const referenceMedian =
        median(reference);
    const pairedMedian =
        median(pairedRatios);
    const candidateFirstMedian =
        median(candidateFirstRatios);
    const referenceFirstMedian =
        median(referenceFirstRatios);

    writeln(
        "thieves=", thiefCount,
        " batch=", batch ? 1 : 0,
        " items=", total,
        " candidate_ns=", candidateMedian,
        " reference_ns=", referenceMedian,
        " paired_ratio=", pairedMedian,
        " candidate_first_ratio=", candidateFirstMedian,
        " reference_first_ratio=", referenceFirstMedian);
}

void main(string[] args)
{
    if (args.length != 6)
    {
        stderr.writeln(
            "usage: contention-parity <thieves> <batch:0|1> <items> <warmups> <samples>");
        return;
    }

    compare(
        to!size_t(args[1]),
        to!int(args[2]) != 0,
        to!size_t(args[3]),
        to!size_t(args[4]),
        to!size_t(args[5]));
}
