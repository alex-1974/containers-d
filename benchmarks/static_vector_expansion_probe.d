/**
 * M4.3 direct container-cost probe.
 *
 * Baseline reproduces the geo-d/geo3-d ExpansionBuffer storage/API shape.
 * Candidate is a thin domain adapter over containers-d's package-internal
 * StaticVector prototype.
 */
module containers.static_vector_expansion_probe;

import containers.internal.static_vector : StaticVector;
import std.conv : to;
import std.math.traits : isFinite;
import std.stdio : stderr, writeln;

enum size_t valueCount = 256;

private struct BaselineExpansionBuffer(size_t Capacity)
if (Capacity > 0)
{
private:
    double[Capacity] _data;
    size_t _length;

public:
    enum size_t capacity = Capacity;

    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _length;
    }

    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _length == 0;
    }

    void clear()
        pure nothrow @safe @nogc
    {
        _length = 0;
    }

    void append(double value)
        pure nothrow @safe @nogc
    {
        assert(isFinite(value));
        assert(_length < Capacity);

        _data[_length] = value;
        ++_length;
    }

    double opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        assert(index < _length);
        return _data[index];
    }
}

private struct CandidateExpansionBuffer(size_t Capacity)
if (Capacity > 0)
{
private:
    StaticVector!(double, Capacity) _data;

public:
    enum size_t capacity = Capacity;

    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _data.length;
    }

    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _data.empty;
    }

    void clear()
        pure nothrow @safe @nogc
    {
        _data.clear();
    }

    void append(double value)
        pure nothrow @safe @nogc
    {
        assert(isFinite(value));
        assert(_data.length < Capacity);

        _data.pushBack(value);
    }

    double opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        assert(index < _data.length);
        return _data[index];
    }
}

private void fillValues(ref double[valueCount] values)
    pure nothrow @safe @nogc
{
    ulong state = 0x9E37_79B9_7F4A_7C15UL;

    foreach (i, ref value; values)
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;

        const long signedValue =
            cast(long) ((state >> 11) & 0x1F_FFFFUL) -
            0x0F_FFFF;

        value =
            cast(double) signedValue /
            1_048_576.0 +
            cast(double) (i & 7) * 0x1p-20;
    }
}

private ulong mixDouble(double value)
    pure nothrow @safe @nogc
{
    return *cast(const(ulong)*) &value;
}

private ulong runProbe(Buffer, size_t Capacity)(
    scope const double[] values,
    size_t rounds)
    @trusted @nogc nothrow
if (Capacity > 0)
{
    Buffer buffer;
    ulong checksum;

    foreach (round; 0 .. rounds)
    {
        buffer.clear();

        const base = round & (valueCount - 1);

        static foreach (i; 0 .. Capacity)
        {
            buffer.append(
                values[(base + i) & (valueCount - 1)]);
        }

        static foreach (i; 0 .. Capacity)
        {
            checksum ^=
                mixDouble(buffer[i]) +
                (cast(ulong) i + 1) *
                0x9E37_79B9_7F4A_7C15UL;
            checksum =
                (checksum << 9) |
                (checksum >> (ulong.sizeof * 8 - 9));
        }
    }

    return checksum;
}

mixin template DefineProbe(size_t Capacity)
{
    alias Baseline = BaselineExpansionBuffer!Capacity;
    alias Candidate = CandidateExpansionBuffer!Capacity;

    static assert(Baseline.sizeof == Candidate.sizeof);

    pragma(inline, false)
    extern(C) ulong bench_baseline(
        scope const double[] values,
        size_t rounds)
    {
        return runProbe!(Baseline, Capacity)(
            values,
            rounds);
    }

    pragma(inline, false)
    extern(C) ulong bench_candidate(
        scope const double[] values,
        size_t rounds)
    {
        return runProbe!(Candidate, Capacity)(
            values,
            rounds);
    }
}

private struct Probe1
{
    mixin DefineProbe!1;
}

private struct Probe2
{
    mixin DefineProbe!2;
}

private struct Probe3
{
    mixin DefineProbe!3;
}

private struct Probe4
{
    mixin DefineProbe!4;
}

private ulong runSelected(
    string variant,
    size_t capacity,
    scope const double[] values,
    size_t rounds)
{
    final switch (capacity)
    {
        case 1:
            return variant == "baseline"
                ? Probe1.bench_baseline(values, rounds)
                : Probe1.bench_candidate(values, rounds);

        case 2:
            return variant == "baseline"
                ? Probe2.bench_baseline(values, rounds)
                : Probe2.bench_candidate(values, rounds);

        case 3:
            return variant == "baseline"
                ? Probe3.bench_baseline(values, rounds)
                : Probe3.bench_candidate(values, rounds);

        case 4:
            return variant == "baseline"
                ? Probe4.bench_baseline(values, rounds)
                : Probe4.bench_candidate(values, rounds);
    }
}

void main(string[] args)
{
    if (args.length != 4)
    {
        stderr.writeln(
            "usage: static-vector-expansion-probe <baseline|candidate> <1|2|3|4> <rounds>");
        return;
    }

    const variant = args[1];
    const capacity = to!size_t(args[2]);
    const rounds = to!size_t(args[3]);

    assert(variant == "baseline" || variant == "candidate");
    assert(capacity >= 1 && capacity <= 4);

    double[valueCount] values = void;
    fillValues(values);

    const checksum =
        runSelected(
            variant,
            capacity,
            values[],
            rounds);

    writeln(
        variant, " ",
        capacity, " ",
        checksum);
}
