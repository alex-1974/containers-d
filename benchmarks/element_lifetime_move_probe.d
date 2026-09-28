/**
 * M4.2 microbenchmark for shared element placement-move construction.
 *
 * Compares the pre-factoring direct placement-new shape against the shared
 * ElementLifetimeOps implementation for a move-only @safe element type.
 *
 * Setup and output remain outside the measured extern(C) benchmark functions.
 */
module containers.element_lifetime_move_probe;

import containers.internal.element_lifetime : PlacementMoveOps;
import std.conv : to;
import std.stdio : stderr, writeln;

private struct MoveValue
{
    ulong a;
    ulong b;
    ulong c;
    ulong d;

    this(ulong seed) @safe @nogc nothrow
    {
        a = seed;
        b = seed ^ 0x9E37_79B9_7F4A_7C15UL;
        c = seed * 0xD6E8_FEB8_6659_FD93UL;
        d = ~seed;
    }

    @disable this(ref return scope MoveValue rhs);

    this(return scope MoveValue rhs) @safe @nogc nothrow
    {
        a = rhs.a;
        b = rhs.b;
        c = rhs.c;
        d = rhs.d;

        rhs.a = 0;
        rhs.b = 0;
        rhs.c = 0;
        rhs.d = 0;
    }

    ulong checksum() const @safe @nogc nothrow
    {
        return (a * 3) ^ (b * 5) ^ (c * 7) ^ (d * 11);
    }
}

private struct MixedInMoveOps
{
    mixin PlacementMoveOps!MoveValue;
}

/**
 * Baseline: exact placement-move shape previously duplicated in the ring
 * containers before M4.2 factoring.
 */
private MoveValue* directPlacementMove(
    MoveValue* target,
    ref MoveValue source) @trusted
{
    assert(target !is null);
    return new (*target) MoveValue(__rvalue(source));
}

private MoveValue* rawTarget(
    ref ubyte[MoveValue.sizeof] raw) @trusted @nogc nothrow
{
    return cast(MoveValue*) raw.ptr;
}

pragma(inline, false)
extern(C) ulong bench_direct(size_t rounds) @safe
{
    align(MoveValue.alignof) ubyte[MoveValue.sizeof] raw = void;
    auto target = rawTarget(raw);

    ulong checksum;

    foreach (i; 0 .. rounds)
    {
        auto source = MoveValue(cast(ulong) i + 1);
        auto placed = directPlacementMove(target, source);

        checksum += placed.checksum;
        destroy!false(*placed);
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_shared(size_t rounds) @safe
{
    align(MoveValue.alignof) ubyte[MoveValue.sizeof] raw = void;
    auto target = rawTarget(raw);

    ulong checksum;

    foreach (i; 0 .. rounds)
    {
        auto source = MoveValue(cast(ulong) i + 1);
        auto placed =
            MixedInMoveOps.placementMoveConstruct(target, source);

        checksum += placed.checksum;
        destroy!false(*placed);
    }

    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: element-lifetime-move-probe <direct|shared> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);
    ulong checksum;

    final switch (args[1])
    {
        case "direct":
            checksum = bench_direct(rounds);
            break;

        case "shared":
            checksum = bench_shared(rounds);
            break;
    }

    writeln(args[1], " ", checksum);
}
