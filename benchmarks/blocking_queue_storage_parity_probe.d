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
            const value = storage.front;
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

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: blocking-queue-storage-parity <candidate|manual> <rounds>");
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
