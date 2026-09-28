/**
 * Issue #31 stage-B performance probe for production-shaped StaticRingBuffer
 * operations.
 *
 * The buffer remains full while each round observes front/back/index, pops the
 * front element and pushes one replacement. Head movement therefore exercises
 * wraparound continuously.
 */
module containers.static_ring_overalignment_perf_probe;

import containers : StaticRingBuffer;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t capacity = 16;
enum size_t valueCount = 256;

private struct NormalValue
{
    ulong value;

    this(ulong value) @safe @nogc nothrow
    {
        this.value = value;
    }
}

align(64) private struct OverAlignedValue
{
    ulong value;
    ubyte[56] padding;

    this(ulong value) @safe @nogc nothrow
    {
        this.value = value;
        padding[] = 0;
    }
}

static assert(OverAlignedValue.alignof == 64);
static assert(OverAlignedValue.sizeof == 64);

private alias NormalRing = StaticRingBuffer!(NormalValue, capacity);
private alias OverRing = StaticRingBuffer!(OverAlignedValue, capacity);

private void fillValues(ref ulong[valueCount] values)
    @safe @nogc nothrow
{
    ulong state = 0xA076_1D64_78BD_642FUL;

    foreach (i, ref value; values)
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        value = state ^ (cast(ulong) i * 0x9E37_79B9_7F4A_7C15UL);
    }
}

private void initialize(Ring, Value)(
    ref Ring ring,
    scope const ulong[] values)
{
    foreach (i; 0 .. capacity)
    {
        auto value = Value(values[i]);
        assert(ring.tryPushBack(value));
    }
}

pragma(inline, false)
extern(C) ulong bench_ring_normal(
    ref NormalRing ring,
    scope const ulong[] values,
    size_t rounds)
{
    ulong checksum;

    foreach (i; 0 .. rounds)
    {
        const logicalIndex = (i * 5) & (capacity - 1);

        checksum += ring.front.value * 3;
        checksum ^= ring.back.value * 5;
        checksum += ring[logicalIndex].value * 7;

        ring.popFront();

        auto incoming =
            NormalValue(values[(i * 13) & (valueCount - 1)] ^ cast(ulong) i);

        if (!ring.tryPushBack(incoming))
            checksum ^= 0xBAD0_BAD0_BAD0_BAD0UL;
    }

    checksum ^= ring.front.value;
    checksum += ring.back.value;
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_ring_over(
    ref OverRing ring,
    scope const ulong[] values,
    size_t rounds)
{
    ulong checksum;

    foreach (i; 0 .. rounds)
    {
        const logicalIndex = (i * 5) & (capacity - 1);

        checksum += ring.front.value * 3;
        checksum ^= ring.back.value * 5;
        checksum += ring[logicalIndex].value * 7;

        ring.popFront();

        auto incoming =
            OverAlignedValue(
                values[(i * 13) & (valueCount - 1)] ^ cast(ulong) i);

        if (!ring.tryPushBack(incoming))
            checksum ^= 0xBAD0_BAD0_BAD0_BAD0UL;
    }

    checksum ^= ring.front.value;
    checksum += ring.back.value;
    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: static-ring-overalignment-perf-probe " ~
            "<normal|over> <rounds>");
        return;
    }

    ulong[valueCount] values = void;
    fillValues(values);

    const rounds = to!size_t(args[2]);
    ulong checksum;

    final switch (args[1])
    {
        case "normal":
        {
            NormalRing ring;
            initialize!(NormalRing, NormalValue)(ring, values[]);
            checksum = bench_ring_normal(ring, values[], rounds);
            break;
        }

        case "over":
        {
            OverRing ring;
            initialize!(OverRing, OverAlignedValue)(ring, values[]);
            checksum = bench_ring_over(ring, values[], rounds);
            break;
        }
    }

    writeln(args[1], " ", checksum);
}
