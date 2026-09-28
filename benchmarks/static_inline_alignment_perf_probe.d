/**
 * Issue #31 stage-A performance probe for inline slot addressing.
 *
 * Measures only lookup/read cost for already-live elements so alignment-base
 * arithmetic is isolated from ring wraparound and element lifetime operations.
 */
module containers.static_inline_alignment_perf_probe;

import containers.internal.inline_storage : InlineRawStorage;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t slotCount = 16;
enum size_t indexCount = 256;

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

static assert(NormalValue.alignof <= (void*).alignof);
static assert(OverAlignedValue.alignof == 64);
static assert(OverAlignedValue.sizeof == 64);

private alias NormalStorage = InlineRawStorage!(NormalValue, slotCount);
private alias OverStorage = InlineRawStorage!(OverAlignedValue, slotCount);

private ulong slotValue(size_t index) @safe @nogc nothrow
{
    return (cast(ulong) index + 1) * 0x9E37_79B9_7F4A_7C15UL ^
        0xD6E8_FEB8_6659_FD93UL;
}

private void fillIndices(ref ubyte[indexCount] indices)
    @safe @nogc nothrow
{
    ulong state = 0xA076_1D64_78BD_642FUL;

    foreach (i, ref index; indices)
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        index = cast(ubyte) ((state ^ cast(ulong) i) & (slotCount - 1));
    }
}

private void initializeNormal(ref NormalStorage storage)
    @trusted @nogc nothrow
{
    foreach (i; 0 .. slotCount)
        new (*storage.slotPointer(i)) NormalValue(slotValue(i));
}

private void initializeOver(ref OverStorage storage)
    @trusted @nogc nothrow
{
    foreach (i; 0 .. slotCount)
        new (*storage.slotPointer(i)) OverAlignedValue(slotValue(i));
}

private void endNormal(ref NormalStorage storage)
    @trusted @nogc nothrow
{
    foreach (i; 0 .. slotCount)
        destroy!false(*storage.slotPointer(i));
}

private void endOver(ref OverStorage storage)
    @trusted @nogc nothrow
{
    foreach (i; 0 .. slotCount)
        destroy!false(*storage.slotPointer(i));
}

pragma(inline, false)
extern(C) ulong bench_normal_selected(
    ref NormalStorage storage,
    scope const ubyte[] indices,
    size_t rounds) @trusted @nogc nothrow
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (index; indices)
            checksum += storage.slotPointer(index).value;
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_over_selected(
    ref OverStorage storage,
    scope const ubyte[] indices,
    size_t rounds) @trusted @nogc nothrow
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (index; indices)
            checksum += storage.slotPointer(index).value;
    }

    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: static-inline-alignment-perf-probe <normal|over> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);

    ubyte[indexCount] indices = void;
    fillIndices(indices);

    ulong checksum;

    final switch (args[1])
    {
        case "normal":
        {
            NormalStorage storage;
            initializeNormal(storage);
            checksum = bench_normal_selected(storage, indices[], rounds);
            endNormal(storage);
            break;
        }

        case "over":
        {
            OverStorage storage;
            initializeOver(storage);
            checksum = bench_over_selected(storage, indices[], rounds);
            endOver(storage);
            break;
        }
    }

    writeln(args[1], " ", checksum);
}
