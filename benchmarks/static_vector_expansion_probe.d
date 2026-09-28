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
    pure nothrow @trusted @nogc
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
            const bits =
                mixDouble(buffer[i]);

            // FNV-style rolling fold with both round and component position.
            // Unlike the earlier symmetric XOR-only fold, this does not cancel
            // back to zero merely because the input period divides the chosen
            // benchmark round count.
            checksum ^=
                bits ^
                ((cast(ulong) round + 1) *
                    0x9E37_79B9_7F4A_7C15UL) ^
                ((cast(ulong) i + 1) *
                    0xD6E8_FEB8_6659_FD93UL);

            checksum *=
                0x0000_0100_0000_01B3UL;
        }
    }

    return checksum;
}

static assert(
    BaselineExpansionBuffer!1.sizeof ==
    CandidateExpansionBuffer!1.sizeof);
static assert(
    BaselineExpansionBuffer!2.sizeof ==
    CandidateExpansionBuffer!2.sizeof);
static assert(
    BaselineExpansionBuffer!3.sizeof ==
    CandidateExpansionBuffer!3.sizeof);
static assert(
    BaselineExpansionBuffer!4.sizeof ==
    CandidateExpansionBuffer!4.sizeof);

pragma(inline, false)
extern(C) ulong bench_baseline_1(
    scope const double[] values,
    size_t rounds)
{
    return runProbe!(BaselineExpansionBuffer!1, 1)(
        values, rounds);
}

pragma(inline, false)
extern(C) ulong bench_candidate_1(
    scope const double[] values,
    size_t rounds)
{
    return runProbe!(CandidateExpansionBuffer!1, 1)(
        values, rounds);
}

pragma(inline, false)
extern(C) ulong bench_baseline_2(
    scope const double[] values,
    size_t rounds)
{
    return runProbe!(BaselineExpansionBuffer!2, 2)(
        values, rounds);
}

pragma(inline, false)
extern(C) ulong bench_candidate_2(
    scope const double[] values,
    size_t rounds)
{
    return runProbe!(CandidateExpansionBuffer!2, 2)(
        values, rounds);
}

pragma(inline, false)
extern(C) ulong bench_baseline_3(
    scope const double[] values,
    size_t rounds)
{
    return runProbe!(BaselineExpansionBuffer!3, 3)(
        values, rounds);
}

pragma(inline, false)
extern(C) ulong bench_candidate_3(
    scope const double[] values,
    size_t rounds)
{
    return runProbe!(CandidateExpansionBuffer!3, 3)(
        values, rounds);
}

pragma(inline, false)
extern(C) ulong bench_baseline_4(
    scope const double[] values,
    size_t rounds)
{
    return runProbe!(BaselineExpansionBuffer!4, 4)(
        values, rounds);
}

pragma(inline, false)
extern(C) ulong bench_candidate_4(
    scope const double[] values,
    size_t rounds)
{
    return runProbe!(CandidateExpansionBuffer!4, 4)(
        values, rounds);
}

private ulong runSelected(
    string variant,
    size_t capacity,
    scope const double[] values,
    size_t rounds)
{
    switch (capacity)
    {
        case 1:
            return variant == "baseline"
                ? bench_baseline_1(values, rounds)
                : bench_candidate_1(values, rounds);

        case 2:
            return variant == "baseline"
                ? bench_baseline_2(values, rounds)
                : bench_candidate_2(values, rounds);

        case 3:
            return variant == "baseline"
                ? bench_baseline_3(values, rounds)
                : bench_candidate_3(values, rounds);

        case 4:
            return variant == "baseline"
                ? bench_baseline_4(values, rounds)
                : bench_candidate_4(values, rounds);

        default:
            assert(0, "unsupported capacity");
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
