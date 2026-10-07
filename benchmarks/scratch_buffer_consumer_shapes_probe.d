module containers.scratch_buffer_consumer_shapes_probe;

import containers.research.scratch_buffer : ResearchScratchBuffer;
import std.conv : to;
import std.stdio : stderr, writeln;

private struct GuiScratchItem
{
    int x;
    int y;
    int w;
    int h;
}

private struct Point2
{
    double x;
    double y;
}

private struct ManualScratch(T)
{
    T[] storage;
    size_t length;

    this(size_t capacity)
    {
        storage = new T[](capacity);
    }

    pragma(inline, true)
    void reset() @safe @nogc nothrow
    {
        length = 0;
    }

    pragma(inline, true)
    bool tryPushBack(T value) @safe @nogc nothrow
    {
        if (length == storage.length)
            return false;

        storage[length++] = value;
        return true;
    }

    pragma(inline, true)
    T[] live() return scope @safe @nogc nothrow
    {
        return storage[0 .. length];
    }
}

private ulong mix(ulong state, ulong value) @safe @nogc nothrow
{
    state ^= value + 0x9E3779B97F4A7C15UL + (state << 6) + (state >> 2);
    return state;
}

private ulong processGui(scope const(GuiScratchItem)[] items)
    @safe @nogc nothrow
{
    ulong checksum = 0x84222325CBF29CE4UL;

    foreach (item; items)
    {
        checksum = mix(checksum, cast(uint)item.x);
        checksum = mix(checksum, cast(uint)item.y);
        checksum = mix(checksum, cast(uint)item.w);
        checksum = mix(checksum, cast(uint)item.h);
    }

    return checksum;
}

private ulong processGeometry(scope const(Point2)[] points)
    @safe @nogc nothrow
{
    ulong checksum = 0xD6E8FEB86659FD93UL;

    foreach (point; points)
    {
        checksum = mix(
            checksum,
            cast(ulong) cast(long)(point.x * 1024.0));
        checksum = mix(
            checksum,
            cast(ulong) cast(long)(point.y * 1024.0));
    }

    return checksum;
}

private ulong processBytes(scope const(ubyte)[] bytes)
    @safe @nogc nothrow
{
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (value; bytes)
        checksum = mix(checksum, value);

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_candidate_dcanvas(
    scope const(int)[] seed,
    size_t rounds)
{
    ResearchScratchBuffer!GuiScratchItem scratch;
    assert(scratch.tryReserve(32));

    ulong checksum;

    foreach (round; 0 .. rounds)
    {
        scratch.reset();

        foreach (i; 0 .. 24)
        {
            const base = seed[i & (seed.length - 1)] ^ cast(int)round;

            assert(scratch.tryPushBack(GuiScratchItem(
                base,
                base + cast(int)i,
                16 + cast(int)(i & 7),
                12 + cast(int)(i & 3))));
        }

        checksum ^= processGui(scratch[]);
    }

    return checksum ^ scratch.highWater;
}

pragma(inline, false)
extern(C) ulong bench_manual_dcanvas(
    scope const(int)[] seed,
    size_t rounds)
{
    auto scratch = ManualScratch!GuiScratchItem(32);
    ulong checksum;

    foreach (round; 0 .. rounds)
    {
        scratch.reset();

        foreach (i; 0 .. 24)
        {
            const base = seed[i & (seed.length - 1)] ^ cast(int)round;

            assert(scratch.tryPushBack(GuiScratchItem(
                base,
                base + cast(int)i,
                16 + cast(int)(i & 7),
                12 + cast(int)(i & 3))));
        }

        checksum ^= processGui(scratch.live());
    }

    return checksum ^ scratch.length;
}

pragma(inline, false)
extern(C) ulong bench_candidate_geometry(
    scope const(int)[] seed,
    size_t rounds)
{
    ResearchScratchBuffer!Point2 scratch;
    assert(scratch.tryReserve(128));

    ulong checksum;

    foreach (round; 0 .. rounds)
    {
        scratch.reset();

        foreach (i; 0 .. 96)
        {
            const a = seed[i & (seed.length - 1)];
            const b = seed[(i + 7) & (seed.length - 1)];

            assert(scratch.tryPushBack(Point2(
                cast(double)(a ^ cast(int)round) * 0.125,
                cast(double)(b + cast(int)i) * 0.25)));
        }

        checksum ^= processGeometry(scratch[]);
    }

    return checksum ^ scratch.highWater;
}

pragma(inline, false)
extern(C) ulong bench_manual_geometry(
    scope const(int)[] seed,
    size_t rounds)
{
    auto scratch = ManualScratch!Point2(128);
    ulong checksum;

    foreach (round; 0 .. rounds)
    {
        scratch.reset();

        foreach (i; 0 .. 96)
        {
            const a = seed[i & (seed.length - 1)];
            const b = seed[(i + 7) & (seed.length - 1)];

            assert(scratch.tryPushBack(Point2(
                cast(double)(a ^ cast(int)round) * 0.125,
                cast(double)(b + cast(int)i) * 0.25)));
        }

        checksum ^= processGeometry(scratch.live());
    }

    return checksum ^ scratch.length;
}

pragma(inline, false)
extern(C) ulong bench_candidate_osm_raster(
    scope const(int)[] seed,
    size_t rounds)
{
    ResearchScratchBuffer!ubyte scratch;
    assert(scratch.tryReserve(4096));

    ulong checksum;

    foreach (round; 0 .. rounds)
    {
        scratch.reset();

        const live =
            2048 +
            (cast(size_t)seed[round & (seed.length - 1)] & 1023);

        foreach (i; 0 .. live)
        {
            const value =
                cast(ubyte)(
                    seed[i & (seed.length - 1)] ^
                    cast(int)(round + i));

            assert(scratch.tryPushBack(value));
        }

        checksum ^= processBytes(scratch[]);
    }

    return checksum ^ scratch.highWater;
}

pragma(inline, false)
extern(C) ulong bench_manual_osm_raster(
    scope const(int)[] seed,
    size_t rounds)
{
    auto scratch = ManualScratch!ubyte(4096);
    size_t highWater;
    ulong checksum;

    foreach (round; 0 .. rounds)
    {
        scratch.reset();

        const live =
            2048 +
            (cast(size_t)seed[round & (seed.length - 1)] & 1023);

        foreach (i; 0 .. live)
        {
            const value =
                cast(ubyte)(
                    seed[i & (seed.length - 1)] ^
                    cast(int)(round + i));

            assert(scratch.tryPushBack(value));
        }

        if (scratch.length > highWater)
            highWater = scratch.length;

        checksum ^= processBytes(scratch.live());
    }

    return checksum ^ highWater;
}

private int[64] makeSeed(size_t rounds)
{
    int[64] seed;
    uint state = cast(uint)rounds ^ 0x7F4A_7C15u;

    foreach (ref value; seed)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        value = cast(int)state;
    }

    return seed;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: consumer-shapes <variant> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);
    const seed = makeSeed(rounds);

    final switch (args[1])
    {
        case "candidate-dcanvas":
            writeln(bench_candidate_dcanvas(seed[], rounds));
            break;
        case "manual-dcanvas":
            writeln(bench_manual_dcanvas(seed[], rounds));
            break;
        case "candidate-geometry":
            writeln(bench_candidate_geometry(seed[], rounds));
            break;
        case "manual-geometry":
            writeln(bench_manual_geometry(seed[], rounds));
            break;
        case "candidate-osm-raster":
            writeln(bench_candidate_osm_raster(seed[], rounds));
            break;
        case "manual-osm-raster":
            writeln(bench_manual_osm_raster(seed[], rounds));
            break;
    }
}
