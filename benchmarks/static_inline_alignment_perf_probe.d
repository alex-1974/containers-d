/**
 * Issue #31 stage-A performance probe for inline slot addressing.
 *
 * Measures only lookup/read cost for already-live elements so alignment-base
 * arithmetic is isolated from ring wraparound and element lifetime operations.
 *
 * Two D shapes are compared:
 *
 * - imported: the reusable InlineRawStorage research type;
 * - local: the same representation generated in the benchmark module through
 *   a typed template mixin, probing whether DMD cross-module abstraction is the
 *   source of semantic/codegen cost.
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

private alias ImportedNormalStorage =
    InlineRawStorage!(NormalValue, slotCount);
private alias ImportedOverStorage =
    InlineRawStorage!(OverAlignedValue, slotCount);

/**
 * Locally generated raw-slot representation.
 *
 * This is deliberately a typed template mixin rather than a string mixin.
 * It injects its own payload and addressing operations, so it has no implicit
 * dependency on pre-existing host fields.
 */
private mixin template LocalRawSlotStorage(
    T,
    size_t Capacity,
    bool DynamicAlignment)
{
    private enum size_t alignmentSlack =
        DynamicAlignment ? T.alignof - 1 : 0;

    static if (DynamicAlignment)
        private ubyte[T.sizeof * Capacity + alignmentSlack] _localBytes = void;
    else
        align(T.alignof)
        private ubyte[T.sizeof * Capacity] _localBytes = void;

    private size_t localBaseOffset() const @safe @nogc nothrow
    {
        static if (!DynamicAlignment)
        {
            return 0;
        }
        else
        {
            const address = (() @trusted =>
                cast(size_t) _localBytes.ptr)();
            const mask = T.alignof - 1;
            const misalignment = address & mask;
            return (T.alignof - misalignment) & mask;
        }
    }

    T* slotPointer(size_t physicalIndex)
        return scope @safe @nogc nothrow
    {
        assert(physicalIndex < Capacity);

        const begin =
            localBaseOffset() + physicalIndex * T.sizeof;

        return (() @trusted =>
            cast(T*) (_localBytes.ptr + begin))();
    }
}

private struct LocalNormalStorage
{
    mixin LocalRawSlotStorage!(NormalValue, slotCount, false);
}

private struct LocalOverStorage
{
    mixin LocalRawSlotStorage!(OverAlignedValue, slotCount, true);
}

static assert(LocalNormalStorage.sizeof ==
    NormalValue.sizeof * slotCount);
static assert(LocalOverStorage.sizeof ==
    OverAlignedValue.sizeof * slotCount + OverAlignedValue.alignof - 1);

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

private void initialize(Storage, Value)(ref Storage storage)
    @trusted @nogc nothrow
{
    foreach (i; 0 .. slotCount)
        new (*storage.slotPointer(i)) Value(slotValue(i));
}

private void finish(Storage)(ref Storage storage)
    @trusted @nogc nothrow
{
    foreach (i; 0 .. slotCount)
        destroy!false(*storage.slotPointer(i));
}

pragma(inline, false)
extern(C) ulong bench_imported_normal(
    ref ImportedNormalStorage storage,
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
extern(C) ulong bench_imported_over(
    ref ImportedOverStorage storage,
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
extern(C) ulong bench_local_normal(
    ref LocalNormalStorage storage,
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
extern(C) ulong bench_local_over(
    ref LocalOverStorage storage,
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
            "usage: static-inline-alignment-perf-probe "
            "<imported-normal|imported-over|local-normal|local-over> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);

    ubyte[indexCount] indices = void;
    fillIndices(indices);

    ulong checksum;

    final switch (args[1])
    {
        case "imported-normal":
        {
            ImportedNormalStorage storage;
            initialize!(ImportedNormalStorage, NormalValue)(storage);
            checksum = bench_imported_normal(storage, indices[], rounds);
            finish(storage);
            break;
        }

        case "imported-over":
        {
            ImportedOverStorage storage;
            initialize!(ImportedOverStorage, OverAlignedValue)(storage);
            checksum = bench_imported_over(storage, indices[], rounds);
            finish(storage);
            break;
        }

        case "local-normal":
        {
            LocalNormalStorage storage;
            initialize!(LocalNormalStorage, NormalValue)(storage);
            checksum = bench_local_normal(storage, indices[], rounds);
            finish(storage);
            break;
        }

        case "local-over":
        {
            LocalOverStorage storage;
            initialize!(LocalOverStorage, OverAlignedValue)(storage);
            checksum = bench_local_over(storage, indices[], rounds);
            finish(storage);
            break;
        }
    }

    writeln(args[1], " ", checksum);
}
