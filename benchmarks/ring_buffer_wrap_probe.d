/**
 * Microbenchmark for StaticRingBuffer physical-index wrap arithmetic.
 *
 * The measured functions use runtime-generated input pairs but compile-time
 * capacities. Callgrind collection is toggled only while each extern(C)
 * benchmark function executes, excluding setup and output.
 */
module ring_buffer_wrap_probe;

import core.stdc.stdlib : strtoul;
import std.stdio : writeln;

enum size_t pairCount = 256;

struct IndexPair
{
    size_t head;
    size_t offset;
}

private void fillPairs(
    ref IndexPair[pairCount] pairs,
    size_t capacity) nothrow @nogc
{
    uint state = 0x9E37_79B9;

    foreach (ref pair; pairs)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        pair.head = state % capacity;

        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        pair.offset = state % capacity;
    }
}

private ulong runBranch(size_t Capacity)(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @nogc
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
        {
            size_t index = pair.head + pair.offset;
            if (index >= Capacity)
                index -= Capacity;
            checksum += index;
        }
    }

    return checksum;
}

private ulong runModulo(size_t Capacity)(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @nogc
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
        {
            const index = (pair.head + pair.offset) % Capacity;
            checksum += index;
        }
    }

    return checksum;
}

private ulong runMask(size_t Capacity)(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @nogc
{
    static assert((Capacity & (Capacity - 1)) == 0,
        "mask probe requires a power-of-two capacity");

    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
        {
            const index = (pair.head + pair.offset) & (Capacity - 1);
            checksum += index;
        }
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_branch_1000(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @nogc
{
    return runBranch!1000(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_modulo_1000(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @nogc
{
    return runModulo!1000(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_branch_1024(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @nogc
{
    return runBranch!1024(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_modulo_1024(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @nogc
{
    return runModulo!1024(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_mask_1024(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @nogc
{
    return runMask!1024(pairs, rounds);
}

void main(string[] args)
{
    if (args.length != 3)
    {
        import core.stdc.stdlib : exit;
        import std.stdio : stderr;

        stderr.writeln("usage: ring-buffer-wrap-probe <variant> <rounds>");
        exit(2);
    }

    const rounds = cast(size_t) strtoul(args[2].ptr, null, 10);

    IndexPair[pairCount] pairs1000 = void;
    IndexPair[pairCount] pairs1024 = void;
    fillPairs(pairs1000, 1000);
    fillPairs(pairs1024, 1024);

    ulong checksum;

    final switch (args[1])
    {
        case "branch-1000":
            checksum = bench_branch_1000(pairs1000[], rounds);
            break;
        case "modulo-1000":
            checksum = bench_modulo_1000(pairs1000[], rounds);
            break;
        case "branch-1024":
            checksum = bench_branch_1024(pairs1024[], rounds);
            break;
        case "modulo-1024":
            checksum = bench_modulo_1024(pairs1024[], rounds);
            break;
        case "mask-1024":
            checksum = bench_mask_1024(pairs1024[], rounds);
            break;
    }

    writeln(args[1], " ", checksum);
}
