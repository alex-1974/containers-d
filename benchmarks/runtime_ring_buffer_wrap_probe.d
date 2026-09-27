/**
 * Microbenchmark for runtime-capacity RingBuffer physical-index wrap arithmetic.
 *
 * Unlike the fixed-capacity probe, every tested capacity is loaded from
 * runtime-generated operation data. This keeps the benchmark from accidentally
 * measuring compile-time constant-capacity strength reduction.
 *
 * The current RingBuffer implementation uses the overflow-safe tail-room form;
 * that form is the semantic baseline for this probe.
 */
module runtime_ring_buffer_wrap_probe;

import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t pairCount = 256;

struct IndexPair
{
    size_t head;
    size_t offset;
    size_t capacity;
    size_t powerOfTwoCapacity;
}

private bool isPowerOfTwo(size_t capacity) nothrow @safe @nogc
{
    return capacity != 0 && (capacity & (capacity - 1)) == 0;
}

private void fillPairs(
    ref IndexPair[pairCount] pairs,
    size_t capacity) nothrow @safe @nogc
{
    assert(capacity != 0);

    const powerOfTwoCapacity = isPowerOfTwo(capacity)
        ? capacity
        : 0;

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

        pair.capacity = capacity;
        pair.powerOfTwoCapacity = powerOfTwoCapacity;
    }
}

private size_t tailRoomIndex(ref const IndexPair pair)
    nothrow @safe @nogc
{
    const tailRoom = pair.capacity - pair.head;

    if (pair.offset < tailRoom)
        return pair.head + pair.offset;

    return pair.offset - tailRoom;
}

private ulong runTailRoom(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
            checksum += tailRoomIndex(pair);
    }

    return checksum;
}

private ulong runAddCarry(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
        {
            size_t index = pair.head + pair.offset;

            // Unsigned carry is detected by index < head. In either the carry
            // case or the ordinary wrapped-ring case, one subtraction is enough
            // because head and offset are each strictly below capacity.
            if (index < pair.head || index >= pair.capacity)
                index -= pair.capacity;

            checksum += index;
        }
    }

    return checksum;
}

private ulong runModulo(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
        {
            // This candidate is measured only for the small capacities selected
            // by the harness. Direct addition-before-modulo is not automatically
            // admissible as the production replacement for the baseline because
            // the public runtime-capacity contract is overflow-safe.
            const index = (pair.head + pair.offset) % pair.capacity;
            checksum += index;
        }
    }

    return checksum;
}

private ulong runMask(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
        {
            assert(pair.powerOfTwoCapacity != 0);
            const index =
                (pair.head + pair.offset) &
                (pair.powerOfTwoCapacity - 1);
            checksum += index;
        }
    }

    return checksum;
}

private ulong runDetect(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
        {
            size_t index;

            if (isPowerOfTwo(pair.capacity))
            {
                index =
                    (pair.head + pair.offset) &
                    (pair.capacity - 1);
            }
            else
            {
                index = tailRoomIndex(pair);
            }

            checksum += index;
        }
    }

    return checksum;
}

private ulong runStored(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const pair; pairs)
        {
            size_t index;

            // Simulates construction-time classification stored in the owning
            // buffer: zero means generic runtime capacity; otherwise the stored
            // value is the power-of-two capacity and also yields the mask.
            if (pair.powerOfTwoCapacity != 0)
            {
                index =
                    (pair.head + pair.offset) &
                    (pair.powerOfTwoCapacity - 1);
            }
            else
            {
                index = tailRoomIndex(pair);
            }

            checksum += index;
        }
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_tailroom(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    return runTailRoom(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_addcarry(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    return runAddCarry(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_modulo(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    return runModulo(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_mask(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    return runMask(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_detect(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    return runDetect(pairs, rounds);
}

pragma(inline, false)
extern(C) ulong bench_stored(
    scope const IndexPair[] pairs,
    size_t rounds) nothrow @safe @nogc
{
    return runStored(pairs, rounds);
}

void main(string[] args)
{
    if (args.length != 4)
    {
        stderr.writeln(
            "usage: runtime-ring-buffer-wrap-probe ",
            "<tailroom|addcarry|modulo|mask|detect|stored> <capacity> <rounds>");
        return;
    }

    const variant = args[1];
    const capacity = to!size_t(args[2]);
    const rounds = to!size_t(args[3]);

    if (capacity == 0)
    {
        stderr.writeln("capacity must be greater than zero");
        return;
    }

    if (variant == "mask" && !isPowerOfTwo(capacity))
    {
        stderr.writeln("mask variant requires a power-of-two capacity");
        return;
    }

    IndexPair[pairCount] pairs = void;
    fillPairs(pairs, capacity);

    ulong checksum;

    final switch (variant)
    {
        case "tailroom":
            checksum = bench_tailroom(pairs[], rounds);
            break;
        case "addcarry":
            checksum = bench_addcarry(pairs[], rounds);
            break;
        case "modulo":
            checksum = bench_modulo(pairs[], rounds);
            break;
        case "mask":
            checksum = bench_mask(pairs[], rounds);
            break;
        case "detect":
            checksum = bench_detect(pairs[], rounds);
            break;
        case "stored":
            checksum = bench_stored(pairs[], rounds);
            break;
    }

    writeln(variant, "-", capacity, " ", checksum);
}
