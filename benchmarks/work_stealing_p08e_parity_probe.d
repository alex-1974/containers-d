module containers.work_stealing_p08e_parity_probe;

import containers.work_stealing_deque :
    WorkStealingDeque;
import concurrency.research.modular_bounded_wsq_batch_marked_top :
    MarkedTopBatchBoundedWorkStealingDeque;

import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t logSize = 10;
enum size_t capacity = size_t(1) << logSize;
enum size_t batchSize = 8;

alias Candidate = WorkStealingDeque!(ulong, capacity);
alias Reference = MarkedTopBatchBoundedWorkStealingDeque!(ulong, logSize);

static assert(Candidate.capacity == Reference.capacity);
static assert(Candidate.sizeof == Reference.sizeof);
static assert(Candidate.alignof == Reference.alignof);

private ulong mix(ulong state, ulong value)
    @safe @nogc nothrow
{
    state ^= value + 0x9E3779B97F4A7C15UL + (state << 6) + (state >> 2);
    return state;
}

private ulong ownerPair(Q)(size_t rounds)
{
    Q queue;
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (i; 0 .. rounds)
    {
        const value = cast(ulong) i + 1;
        assert(queue.tryPush(value));

        const result = queue.pop();
        assert(result.found);
        assert(result.value == value);

        checksum = mix(checksum, result.value);
    }

    return checksum;
}

private ulong singleSteal(Q)(size_t rounds)
{
    Q queue;
    ulong checksum = 0x84222325CBF29CE4UL;

    foreach (i; 0 .. rounds)
    {
        const value = cast(ulong) i + 1;
        assert(queue.tryPush(value));

        const result = queue.steal();
        assert(result.found);
        assert(result.value == value);

        checksum = mix(checksum, result.value);
    }

    return checksum;
}

private ulong batchSteal(Q)(size_t rounds)
{
    Q queue;
    ulong checksum = 0xD6E8FEB86659FD93UL;
    ulong[batchSize] output;

    foreach (round; 0 .. rounds)
    {
        foreach (i; 0 .. batchSize)
        {
            const value =
                cast(ulong) (
                    round * batchSize +
                    i + 1);

            assert(queue.tryPush(value));
        }

        const taken = queue.stealBatch(output[]);
        assert(taken == batchSize);

        foreach (value; output[])
            checksum = mix(checksum, value);
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_candidate_owner_pair(size_t rounds)
{
    return ownerPair!Candidate(rounds);
}

pragma(inline, false)
extern(C) ulong bench_reference_owner_pair(size_t rounds)
{
    return ownerPair!Reference(rounds);
}

pragma(inline, false)
extern(C) ulong bench_candidate_single_steal(size_t rounds)
{
    return singleSteal!Candidate(rounds);
}

pragma(inline, false)
extern(C) ulong bench_reference_single_steal(size_t rounds)
{
    return singleSteal!Reference(rounds);
}

pragma(inline, false)
extern(C) ulong bench_candidate_batch_steal(size_t rounds)
{
    return batchSteal!Candidate(rounds);
}

pragma(inline, false)
extern(C) ulong bench_reference_batch_steal(size_t rounds)
{
    return batchSteal!Reference(rounds);
}

private ulong selected(string variant, size_t rounds)
{
    final switch (variant)
    {
        case "candidate-owner":
            return bench_candidate_owner_pair(rounds);
        case "reference-owner":
            return bench_reference_owner_pair(rounds);
        case "candidate-steal":
            return bench_candidate_single_steal(rounds);
        case "reference-steal":
            return bench_reference_single_steal(rounds);
        case "candidate-batch":
            return bench_candidate_batch_steal(rounds);
        case "reference-batch":
            return bench_reference_batch_steal(rounds);
    }
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: work-stealing-p08e-parity <variant> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);
    writeln(args[1], " ", selected(args[1], rounds));
}
