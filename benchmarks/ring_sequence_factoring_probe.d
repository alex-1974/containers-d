/**
 * M4.4 direct-vs-factored ring sequencing probe.
 */
module containers.ring_sequence_factoring_probe;

import containers.internal.ring_sequence : RingSequenceOps;
import std.conv : to;
import std.stdio : stderr, writeln;

private struct BaselineStatic(size_t Capacity)
if (Capacity > 0)
{
private:
    size_t _head;
    size_t _length;

    pragma(inline, true)
    size_t physicalIndex(size_t logicalIndex) const nothrow @safe @nogc
    {
        assert(logicalIndex < Capacity);
        static if ((Capacity & (Capacity - 1)) == 0)
            return (_head + logicalIndex) & (Capacity - 1);
        else
        {
            size_t index = _head + logicalIndex;
            if (index >= Capacity)
                index -= Capacity;
            return index;
        }
    }

    pragma(inline, true)
    void advanceHead() nothrow @safe @nogc
    {
        ++_head;
        if (_head == Capacity)
            _head = 0;
    }

    pragma(inline, true)
    void consumeFrontState() nothrow @safe @nogc
    {
        assert(_length > 0);
        --_length;
        if (_length == 0)
            _head = 0;
        else
            advanceHead();
    }

public:
    pragma(inline, true)
    ulong cycle(size_t round) nothrow @safe @nogc
    {
        _head = round % Capacity;
        _length = Capacity;

        ulong checksum;
        foreach (i; 0 .. Capacity)
            checksum = checksum * 131 + physicalIndex(i) + 1;

        consumeFrontState();
        checksum = checksum * 131 + _head + _length * 17;
        return checksum;
    }
}

private struct FactoredStatic(size_t Capacity)
if (Capacity > 0)
{
    enum size_t capacity = Capacity;

private:
    mixin RingSequenceOps!Capacity;

public:
    pragma(inline, true)
    ulong cycle(size_t round) nothrow @safe @nogc
    {
        _head = round % Capacity;
        _length = Capacity;

        ulong checksum;
        foreach (i; 0 .. Capacity)
            checksum = checksum * 131 + physicalIndex(i) + 1;

        consumeFrontState();
        checksum = checksum * 131 + _head + _length * 17;
        return checksum;
    }
}

private struct BaselineRuntime
{
private:
    size_t _capacity;
    size_t _head;
    size_t _length;

    @property size_t capacity() const nothrow @safe @nogc
    {
        return _capacity;
    }

    pragma(inline, true)
    size_t physicalIndex(size_t logicalIndex) const nothrow @safe @nogc
    {
        assert(logicalIndex < capacity);
        assert(capacity != 0);
        assert(_head < capacity);

        const tailRoom = capacity - _head;
        if (logicalIndex < tailRoom)
            return _head + logicalIndex;
        return logicalIndex - tailRoom;
    }

    pragma(inline, true)
    void advanceHead() nothrow @safe @nogc
    {
        assert(capacity != 0);
        assert(_head < capacity);
        ++_head;
        if (_head == capacity)
            _head = 0;
    }

    pragma(inline, true)
    void consumeFrontState() nothrow @safe @nogc
    {
        assert(_length > 0);
        --_length;
        if (_length == 0)
            _head = 0;
        else
            advanceHead();
    }

public:
    this(size_t capacity) nothrow @safe @nogc
    {
        _capacity = capacity;
    }

    pragma(inline, true)
    ulong cycle(size_t round) nothrow @safe @nogc
    {
        _head = round % capacity;
        _length = capacity;

        ulong checksum;
        foreach (i; 0 .. capacity)
            checksum = checksum * 131 + physicalIndex(i) + 1;

        consumeFrontState();
        checksum = checksum * 131 + _head + _length * 17;
        return checksum;
    }
}

private struct FactoredRuntime
{
private:
    size_t _capacity;

    @property size_t capacity() const nothrow @safe @nogc
    {
        return _capacity;
    }

    mixin RingSequenceOps;

public:
    this(size_t capacity) nothrow @safe @nogc
    {
        _capacity = capacity;
    }

    pragma(inline, true)
    ulong cycle(size_t round) nothrow @safe @nogc
    {
        _head = round % capacity;
        _length = capacity;

        ulong checksum;
        foreach (i; 0 .. capacity)
            checksum = checksum * 131 + physicalIndex(i) + 1;

        consumeFrontState();
        checksum = checksum * 131 + _head + _length * 17;
        return checksum;
    }
}

static assert(BaselineStatic!4.sizeof == FactoredStatic!4.sizeof);
static assert(BaselineStatic!7.sizeof == FactoredStatic!7.sizeof);
static assert(BaselineRuntime.sizeof == FactoredRuntime.sizeof);
static assert(FactoredStatic!4.sizeof == 2 * size_t.sizeof);
static assert(FactoredStatic!7.sizeof == 2 * size_t.sizeof);
static assert(FactoredRuntime.sizeof == 3 * size_t.sizeof);

private ulong run(S)(ref S sequence, size_t rounds) nothrow @safe @nogc
{
    ulong checksum = 0xCBF29CE484222325UL;
    foreach (round; 0 .. rounds)
    {
        checksum ^= sequence.cycle(round);
        checksum *= 0x100000001B3UL;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_static4_baseline(size_t rounds)
{
    BaselineStatic!4 s;
    return run(s, rounds);
}

pragma(inline, false)
extern(C) ulong bench_static4_factored(size_t rounds)
{
    FactoredStatic!4 s;
    return run(s, rounds);
}

pragma(inline, false)
extern(C) ulong bench_static7_baseline(size_t rounds)
{
    BaselineStatic!7 s;
    return run(s, rounds);
}

pragma(inline, false)
extern(C) ulong bench_static7_factored(size_t rounds)
{
    FactoredStatic!7 s;
    return run(s, rounds);
}

pragma(inline, false)
extern(C) ulong bench_runtime7_baseline(size_t rounds)
{
    auto s = BaselineRuntime(7);
    return run(s, rounds);
}

pragma(inline, false)
extern(C) ulong bench_runtime7_factored(size_t rounds)
{
    auto s = FactoredRuntime(7);
    return run(s, rounds);
}

private ulong selected(string variant, size_t rounds)
{
    final switch (variant)
    {
        case "static4-baseline": return bench_static4_baseline(rounds);
        case "static4-factored": return bench_static4_factored(rounds);
        case "static7-baseline": return bench_static7_baseline(rounds);
        case "static7-factored": return bench_static7_factored(rounds);
        case "runtime7-baseline": return bench_runtime7_baseline(rounds);
        case "runtime7-factored": return bench_runtime7_factored(rounds);
    }
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln("usage: ring-sequence-factoring-probe <variant> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);
    writeln(args[1], " ", selected(args[1], rounds));
}
