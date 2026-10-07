module containers.scratch_buffer_reuse_probe;

import containers.research.scratch_buffer : ResearchScratchBuffer;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t capacity = 64;
alias Candidate = ResearchScratchBuffer!int;

private struct ManualScratch
{
    int[] storage;
    size_t length;
    size_t highWater;

    this(size_t capacity)
    {
        storage = new int[](capacity);
    }

    bool tryPushBack(int value) @safe @nogc nothrow
    {
        if (length == storage.length)
            return false;

        storage[length++] = value;

        if (length > highWater)
            highWater = length;

        return true;
    }

    int[] live() return scope @safe @nogc nothrow
    {
        return storage[0 .. length];
    }

    void reset() @safe @nogc nothrow
    {
        length = 0;
    }
}

private ulong mix(ulong state, int value) @safe @nogc nothrow
{
    return
        (state ^ cast(uint) value) *
        0x100000001B3UL;
}

pragma(inline, false)
extern(C) ulong bench_candidate(
    ref Candidate scratch,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (round; 0 .. rounds)
    {
        scratch.reset();

        foreach (i; 0 .. capacity)
        {
            const value =
                cast(int) (
                    round * capacity + i);

            assert(scratch.tryPushBack(value));
        }

        foreach (value; scratch[])
            checksum = mix(checksum, value);
    }

    checksum ^= scratch.highWater;
    checksum ^= scratch.capacity << 32;
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_manual(
    ref ManualScratch scratch,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (round; 0 .. rounds)
    {
        scratch.reset();

        foreach (i; 0 .. capacity)
        {
            const value =
                cast(int) (
                    round * capacity + i);

            assert(scratch.tryPushBack(value));
        }

        foreach (value; scratch.live())
            checksum = mix(checksum, value);
    }

    checksum ^= scratch.highWater;
    checksum ^= scratch.storage.length << 32;
    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: scratch-buffer-reuse-probe <candidate|manual> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);

    final switch (args[1])
    {
        case "candidate":
        {
            auto scratch = Candidate(capacity);
            writeln("candidate ", bench_candidate(scratch, rounds));
            break;
        }

        case "manual":
        {
            auto scratch = ManualScratch(capacity);
            writeln("manual ", bench_manual(scratch, rounds));
            break;
        }
    }
}
