/**
 * M4 / issue #31 probe for lvalue construction into raw container storage.
 *
 * Compares core.lifetime.emplace with direct D placement-copy construction.
 * The semantic gate includes ordinary copy constructors, legacy postblits and
 * disabled default initialization before any performance result is accepted.
 */
module containers.element_lifetime_copy_probe;

import core.lifetime : emplace;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t valueCount = 256;

private struct PlainValue
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

    ulong checksum() const @safe @nogc nothrow
    {
        return (a * 3) ^ (b * 5) ^ (c * 7) ^ (d * 11);
    }
}

private struct CopyCtorValue
{
    static int copies;
    int value;

    this(int value) @safe @nogc nothrow
    {
        this.value = value;
    }

    this(ref return scope CopyCtorValue rhs) @safe @nogc nothrow
    {
        value = rhs.value;
        ++copies;
    }
}

private struct PostblitValue
{
    static int postblits;
    int value;

    this(this) @safe @nogc nothrow
    {
        ++postblits;
    }
}

private struct DisabledInitCopy
{
    static int copies;
    int value;

    @disable this();

    this(int value) @safe @nogc nothrow
    {
        this.value = value;
    }

    this(ref return scope DisabledInitCopy rhs) @safe @nogc nothrow
    {
        value = rhs.value;
        ++copies;
    }
}

private enum bool fastCopyEligible(T) =
    is(T == struct) &&
    !__traits(hasCopyConstructor, T) &&
    !__traits(hasPostblit, T) &&
    !__traits(needsDestruction, T) &&
    !__traits(hasMember, T, "opAssign");

private T* fastCopyEmplace(T)(
    T* target,
    ref T source) @trusted
if (fastCopyEligible!T)
{
    assert(target !is null);

    // core.lifetime.moveEmplace uses the same direct assignment into an
    // uninitialized target for simple assignable structs. Unlike moveEmplace,
    // this copy path deliberately leaves source untouched.
    *target = source;
    return target;
}

private T* emplaceCopy(T)(
    T* target,
    ref T source)
{
    assert(target !is null);
    return emplace(target, source);
}

private T* rawTarget(T)(ref ubyte[T.sizeof] raw)
    @trusted @nogc nothrow
{
    return cast(T*) raw.ptr;
}

private void verifySemantics()
{
    static assert(fastCopyEligible!PlainValue);
    static assert(!fastCopyEligible!CopyCtorValue);
    static assert(!fastCopyEligible!PostblitValue);
    static assert(!fastCopyEligible!DisabledInitCopy);

    {
        align(PlainValue.alignof)
            ubyte[PlainValue.sizeof] raw = void;
        auto target = rawTarget!PlainValue(raw);
        auto source = PlainValue(11);

        auto placed = fastCopyEmplace(target, source);
        assert(placed is target);
        assert(placed.checksum == source.checksum);
        assert(source.a == 11);
        destroy!false(*placed);
    }

    // Complex copy semantics remain on core.lifetime.emplace.
    {
        align(CopyCtorValue.alignof)
            ubyte[CopyCtorValue.sizeof] raw = void;
        auto target = rawTarget!CopyCtorValue(raw);
        auto source = CopyCtorValue(17);

        CopyCtorValue.copies = 0;
        auto placed = emplaceCopy(target, source);
        assert(placed.value == 17);
        assert(source.value == 17);
        assert(CopyCtorValue.copies == 1);
        destroy!false(*placed);
    }

    {
        align(PostblitValue.alignof)
            ubyte[PostblitValue.sizeof] raw = void;
        auto target = rawTarget!PostblitValue(raw);
        PostblitValue source;
        source.value = 23;

        PostblitValue.postblits = 0;
        auto placed = emplaceCopy(target, source);
        assert(placed.value == 23);
        assert(PostblitValue.postblits == 1);
        destroy!false(*placed);
    }

    {
        align(DisabledInitCopy.alignof)
            ubyte[DisabledInitCopy.sizeof] raw = void;
        auto target = rawTarget!DisabledInitCopy(raw);
        auto source = DisabledInitCopy(31);

        DisabledInitCopy.copies = 0;
        auto placed = emplaceCopy(target, source);
        assert(placed.value == 31);
        assert(DisabledInitCopy.copies == 1);
        destroy!false(*placed);
    }
}

private void fillValues(ref PlainValue[valueCount] values)
    @safe @nogc nothrow
{
    foreach (i, ref value; values)
        value = PlainValue(cast(ulong) i + 1);
}

pragma(inline, false)
extern(C) ulong bench_emplace(
    PlainValue* values,
    size_t count,
    size_t rounds)
{
    align(PlainValue.alignof) ubyte[PlainValue.sizeof] raw = void;
    auto target = rawTarget!PlainValue(raw);

    ulong checksum;
    size_t round;

    while (round < rounds)
    {
        size_t i;
        while (i < count)
        {
            auto placed = emplaceCopy(target, values[i]);
            checksum += placed.checksum;
            destroy!false(*placed);
            ++i;
        }
        ++round;
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_fast(
    PlainValue* values,
    size_t count,
    size_t rounds)
{
    align(PlainValue.alignof) ubyte[PlainValue.sizeof] raw = void;
    auto target = rawTarget!PlainValue(raw);

    ulong checksum;
    size_t round;

    while (round < rounds)
    {
        size_t i;
        while (i < count)
        {
            auto placed = fastCopyEmplace(target, values[i]);
            checksum += placed.checksum;
            destroy!false(*placed);
            ++i;
        }
        ++round;
    }

    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: element-lifetime-copy-probe <emplace|fast> <rounds>");
        return;
    }

    verifySemantics();

    PlainValue[valueCount] values = void;
    fillValues(values);

    const rounds = to!size_t(args[2]);
    ulong checksum;

    final switch (args[1])
    {
        case "emplace":
            checksum = bench_emplace(values.ptr, values.length, rounds);
            break;
        case "fast":
            checksum = bench_fast(values.ptr, values.length, rounds);
            break;
    }

    writeln(args[1], " ", checksum);
}
