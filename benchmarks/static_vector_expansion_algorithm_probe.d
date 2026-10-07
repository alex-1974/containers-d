/**
 * M4.3 algorithm-level StaticVector probe.
 *
 * Exercises the same fixed-capacity buffer mechanics inside a representative
 * binary64 expansion-sum algorithm derived from the structure used by geo-d
 * and geo3-d.
 */
module containers.static_vector_expansion_algorithm_probe;

import containers.internal.static_vector : StaticVector;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t inputCount = 256;

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

private struct TwoComponent
{
    double high;
    double low;
}

pragma(inline, true)
private double finiteMagnitude(double value)
    pure nothrow @safe @nogc
{
    return value < 0.0 ? -value : value;
}

pragma(inline, true)
private TwoComponent twoSum(double a, double b)
    pure nothrow @safe @nogc
{
    const x = a + b;
    const bVirtual = x - a;
    const aVirtual = x - bVirtual;
    const bRoundoff = b - bVirtual;
    const aRoundoff = a - aVirtual;
    const y = aRoundoff + bRoundoff;

    return TwoComponent(x, y);
}

pragma(inline, true)
private TwoComponent fastTwoSum(double a, double b)
    pure nothrow @safe @nogc
{
    assert(finiteMagnitude(a) >= finiteMagnitude(b));

    const x = a + b;
    const bVirtual = x - a;
    const y = b - bVirtual;

    return TwoComponent(x, y);
}

/**
 * Representative copy of the geo expansion-sum control flow.
 *
 * Inputs are ordered least-significant to most-significant. ResultCapacity
 * must accommodate the maximum E+F active components.
 */
private void fastExpansionSumZeroElim(E, F, H)(
    ref const E e,
    ref const F f,
    ref H h)
    pure nothrow @safe @nogc
if (H.capacity >= E.capacity + F.capacity)
{
    h.clear();

    if (e.empty)
    {
        foreach (index; 0 .. f.length)
        {
            const component = f[index];
            if (component != 0.0)
                h.append(component);
        }

        if (h.empty)
            h.append(0.0);

        return;
    }

    if (f.empty)
    {
        foreach (index; 0 .. e.length)
        {
            const component = e[index];
            if (component != 0.0)
                h.append(component);
        }

        if (h.empty)
            h.append(0.0);

        return;
    }

    size_t eIndex;
    size_t fIndex;

    double eNow = e[eIndex];
    double fNow = f[fIndex];
    double q;

    if (finiteMagnitude(eNow) <= finiteMagnitude(fNow))
    {
        q = eNow;
        ++eIndex;
    }
    else
    {
        q = fNow;
        ++fIndex;
    }

    if (eIndex < e.length && fIndex < f.length)
    {
        double next;

        if (finiteMagnitude(e[eIndex]) <= finiteMagnitude(f[fIndex]))
        {
            next = e[eIndex];
            ++eIndex;
        }
        else
        {
            next = f[fIndex];
            ++fIndex;
        }

        const initial = fastTwoSum(next, q);

        if (initial.low != 0.0)
            h.append(initial.low);

        q = initial.high;

        while (eIndex < e.length && fIndex < f.length)
        {
            if (finiteMagnitude(e[eIndex]) <= finiteMagnitude(f[fIndex]))
            {
                next = e[eIndex];
                ++eIndex;
            }
            else
            {
                next = f[fIndex];
                ++fIndex;
            }

            const sum = twoSum(q, next);

            if (sum.low != 0.0)
                h.append(sum.low);

            q = sum.high;
        }
    }

    while (eIndex < e.length)
    {
        const sum = twoSum(q, e[eIndex]);

        if (sum.low != 0.0)
            h.append(sum.low);

        q = sum.high;
        ++eIndex;
    }

    while (fIndex < f.length)
    {
        const sum = twoSum(q, f[fIndex]);

        if (sum.low != 0.0)
            h.append(sum.low);

        q = sum.high;
        ++fIndex;
    }

    if (q != 0.0 || h.empty)
        h.append(q);
}

private void fillInputs(ref double[inputCount] values)
    pure nothrow @safe @nogc
{
    ulong state = 0x243F_6A88_85A3_08D3UL;

    foreach (i, ref value; values)
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;

        // Keep the main magnitudes in a compact exact integer range. The low
        // components are derived separately as exact powers of two.
        const long signedValue =
            cast(long) ((state >> 17) & 0x3F_FFFFUL) -
            0x1F_FFFF;

        value =
            cast(double) signedValue +
            cast(double) (i & 15) * 0.25;
    }
}

private ulong mixDouble(double value)
    pure nothrow @trusted @nogc
{
    return *cast(const(ulong)*) &value;
}

private ulong runAlgorithm(
    Buffer2,
    Buffer4
)(
    scope const double[] values,
    size_t rounds)
    @trusted @nogc nothrow
{
    Buffer2 e;
    Buffer2 f;
    Buffer4 h;

    ulong checksum =
        0xCBF2_9CE4_8422_2325UL;

    foreach (round; 0 .. rounds)
    {
        e.clear();
        f.clear();

        const base = round & (inputCount - 1);

        // Valid two-component expansion-shaped inputs: the low component is
        // tiny relative to the high component.
        const eHigh = values[base];
        const fHigh = values[(base + 73) & (inputCount - 1)];

        const eLow =
            ((round & 1) == 0 ? 1.0 : -1.0) *
            0x1p-40;

        const fLow =
            ((round & 2) == 0 ? 1.0 : -1.0) *
            0x1p-41;

        e.append(eLow);
        e.append(eHigh);

        f.append(fLow);
        f.append(fHigh);

        fastExpansionSumZeroElim(e, f, h);

        checksum ^=
            (cast(ulong) h.length + 1) *
            0x9E37_79B9_7F4A_7C15UL;

        foreach (index; 0 .. h.length)
        {
            checksum ^=
                mixDouble(h[index]) +
                (cast(ulong) index + 1) *
                0xD6E8_FEB8_6659_FD93UL;

            checksum *=
                0x0000_0100_0000_01B3UL;
        }

        checksum ^=
            (cast(ulong) round + 1) *
            0x94D0_49BB_1331_11EBUL;
    }

    return checksum;
}

alias Baseline2 = BaselineExpansionBuffer!2;
alias Baseline4 = BaselineExpansionBuffer!4;
alias Candidate2 = CandidateExpansionBuffer!2;
alias Candidate4 = CandidateExpansionBuffer!4;

static assert(Baseline2.sizeof == Candidate2.sizeof);
static assert(Baseline4.sizeof == Candidate4.sizeof);

pragma(inline, false)
extern(C) ulong bench_baseline(
    scope const double[] values,
    size_t rounds)
{
    return runAlgorithm!(Baseline2, Baseline4)(
        values,
        rounds);
}

pragma(inline, false)
extern(C) ulong bench_candidate(
    scope const double[] values,
    size_t rounds)
{
    return runAlgorithm!(Candidate2, Candidate4)(
        values,
        rounds);
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: static-vector-expansion-algorithm-probe <baseline|candidate> <rounds>");
        return;
    }

    const variant = args[1];
    const rounds = to!size_t(args[2]);

    assert(variant == "baseline" || variant == "candidate");

    double[inputCount] values = void;
    fillInputs(values);

    const checksum =
        variant == "baseline"
        ? bench_baseline(values[], rounds)
        : bench_candidate(values[], rounds);

    writeln(variant, " ", checksum);
}
