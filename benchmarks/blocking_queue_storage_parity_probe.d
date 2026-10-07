module containers.blocking_queue_storage_parity_probe;

import containers.runtime_ring_buffer : RingBuffer;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t capacity = 64;

private struct ManualRing
{
    int[] storage;
    size_t head;
    size_t length;

    this(size_t capacity)
    {
        storage = new int[](capacity);
    }

    bool tryPushBack(int value) @safe @nogc nothrow
    {
        if (length == storage.length)
            return false;

        const physical =
            (head + length) % storage.length;

        storage[physical] = value;
        ++length;
        return true;
    }

    int popFront() @safe @nogc nothrow
    {
        assert(length != 0);

        const value = storage[head];

        ++head;
        if (head == storage.length)
            head = 0;

        --length;

        if (length == 0)
            head = 0;

        return value;
    }
}

private ulong mix(ulong state, int value) @safe @nogc nothrow
{
    return
        (state ^ cast(uint)value) *
        0x100000001B3UL;
}

pragma(inline, false)
extern(C) ulong bench_candidate(
    ref RingBuffer!int storage,
    scope const(int)[] input,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (round; 0 .. rounds)
    {
        foreach (i, seed; input)
        {
            const value =
                seed ^ cast(int)(round + i);

            assert(storage.tryPushBack(value));
        }

        foreach (_; 0 .. input.length)
        {
            const int value = storage.front;
            storage.popFront();
            checksum = mix(checksum, value);
        }
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_manual(
    ref ManualRing storage,
    scope const(int)[] input,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (round; 0 .. rounds)
    {
        foreach (i, seed; input)
        {
            const value =
                seed ^ cast(int)(round + i);

            assert(storage.tryPushBack(value));
        }

        foreach (_; 0 .. input.length)
            checksum = mix(checksum, storage.popFront());
    }

    return checksum;
}

private ulong verifyStepwise(
    scope const(int)[] input,
    size_t rounds)
{
    auto candidate = RingBuffer!int(capacity);
    auto manual = ManualRing(capacity);

    ulong checksum = 0xCBF29CE484222325UL;

    foreach (round; 0 .. rounds)
    {
        foreach (i, seed; input)
        {
            const value =
                seed ^ cast(int)(round + i);

            const candidateAccepted =
                candidate.tryPushBack(value);
            const manualAccepted =
                manual.tryPushBack(value);

            if (candidateAccepted != manualAccepted ||
                !candidateAccepted)
            {
                stderr.writeln(
                    "push mismatch round=", round,
                    " index=", i,
                    " candidate=", candidateAccepted,
                    " manual=", manualAccepted);
                return ulong.max;
            }
        }

        foreach (_; 0 .. input.length)
        {
            if (candidate.empty || manual.length == 0)
            {
                stderr.writeln(
                    "empty mismatch round=", round);
                return ulong.max;
            }

            const int candidateValue = candidate.front;
            const int manualValue = manual.popFront();

            if (candidateValue != manualValue)
            {
                stderr.writeln(
                    "value mismatch round=", round,
                    " candidate=", candidateValue,
                    " manual=", manualValue);
                return ulong.max;
            }

            candidate.popFront();

            checksum = mix(checksum, candidateValue);
        }

        if (!candidate.empty || manual.length != 0)
        {
            stderr.writeln(
                "post-round state mismatch round=", round,
                " candidateEmpty=", candidate.empty,
                " manualLength=", manual.length);
            return ulong.max;
        }
    }

    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: blocking-queue-storage-parity <candidate|manual|verify> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);

    int[capacity] input;
    uint state =
        cast(uint)rounds ^
        0x6C8E_9CF5u;

    foreach (ref value; input)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        value = cast(int)state;
    }

    final switch (args[1])
    {
        case "verify":
        {
            writeln("verify ",
                verifyStepwise(input[], rounds));
            break;
        }

        case "candidate":
        {
            auto storage = RingBuffer!int(capacity);
            writeln("candidate ",
                bench_candidate(storage, input[], rounds));
            break;
        }

        case "manual":
        {
            auto storage = ManualRing(capacity);
            writeln("manual ",
                bench_manual(storage, input[], rounds));
            break;
        }
    }
}
