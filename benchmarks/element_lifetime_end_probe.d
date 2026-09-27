/**
 * M4.2 microbenchmark for shared element lifetime termination.
 *
 * Compares the historical direct destroy!false shape against the shared
 * EndElementLifetimeOps implementation for an element with an elaborate
 * destructor.
 */
module containers.element_lifetime_end_probe;

import containers.internal.element_lifetime : EndElementLifetimeOps;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t valueCount = 256;

private __gshared ulong destructionSink;

private struct DestroyValue
{
    ulong value;

    this(ulong value) @safe @nogc nothrow
    {
        this.value = value;
    }

    ~this() @nogc nothrow
    {
        destructionSink += value;
    }
}

private struct MixedInEndOps
{
    mixin EndElementLifetimeOps!DestroyValue;
}


private void fillValues(
    ref ulong[valueCount] values) @safe @nogc nothrow
{
    ulong state = 0x9E37_79B9_7F4A_7C15UL;

    foreach (i, ref value; values)
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        value = state ^ cast(ulong) i;
    }
}

private DestroyValue* rawTarget(
    ref ubyte[DestroyValue.sizeof] raw) @trusted @nogc nothrow
{
    return cast(DestroyValue*) raw.ptr;
}

private void constructAt(
    DestroyValue* target,
    ulong value) @trusted @nogc nothrow
{
    new (*target) DestroyValue(value);
}

/**
 * Baseline: exact direct destroy shape currently used in the ring containers.
 */
private void directEnd(DestroyValue* slot)
{
    assert(slot !is null);
    destroy!false(*slot);
}

pragma(inline, false)
extern(C) ulong bench_direct(
    scope const ulong[] values,
    size_t rounds)
{
    align(DestroyValue.alignof) ubyte[DestroyValue.sizeof] raw = void;
    auto slot = rawTarget(raw);

    destructionSink = 0;

    foreach (_; 0 .. rounds)
    {
        foreach (value; values)
        {
            constructAt(slot, value);
            directEnd(slot);
        }
    }

    return destructionSink;
}

pragma(inline, false)
extern(C) ulong bench_shared(
    scope const ulong[] values,
    size_t rounds)
{
    align(DestroyValue.alignof) ubyte[DestroyValue.sizeof] raw = void;
    auto slot = rawTarget(raw);

    destructionSink = 0;

    foreach (_; 0 .. rounds)
    {
        foreach (value; values)
        {
            constructAt(slot, value);
            MixedInEndOps.endElementLifetime(slot);
        }
    }

    return destructionSink;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: element-lifetime-end-probe <direct|shared> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);

    ulong[valueCount] values = void;
    fillValues(values);

    ulong checksum;

    final switch (args[1])
    {
        case "direct":
            checksum = bench_direct(values[], rounds);
            break;

        case "shared":
            checksum = bench_shared(values[], rounds);
            break;
    }

    writeln(args[1], " ", checksum);
}
