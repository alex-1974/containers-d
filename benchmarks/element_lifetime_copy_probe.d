/**
 * M4 / issue #31 probe for lvalue construction into raw container storage.
 *
 * Compares core.lifetime.emplace with direct D placement-copy construction.
 * The semantic gate includes ordinary copy constructors, legacy postblits and
 * disabled default initialization before any performance result is accepted.
 */
module containers.element_lifetime_copy_probe;

import core.lifetime : copyEmplace, emplace;
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

private T* copyEmplaceCopy(T)(
    T* target,
    ref T source) @trusted
{
    assert(target !is null);
    copyEmplace(source, *target);
    return target;
}

pragma(inline, true)
private T* localBlitCopy(T)(
    T* target,
    ref T source) @trusted @nogc nothrow
if (is(T == struct) &&
    !__traits(hasPostblit, T) &&
    !__traits(hasCopyConstructor, T))
{
    assert(target !is null);

    // Mirrors core.lifetime.copyEmplace's simple-struct branch, but expresses
    // the fixed-size blit locally so DMD can lower it without an out-of-line
    // memcpy call.
    *cast(ubyte[T.sizeof]*) target =
        *cast(ubyte[T.sizeof]*) &source;

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
    // Trivial/simple struct.
    {
        align(PlainValue.alignof)
            ubyte[PlainValue.sizeof] raw = void;
        auto target = rawTarget!PlainValue(raw);
        auto source = PlainValue(11);

        auto placed = copyEmplaceCopy(target, source);
        assert(placed is target);
        assert(placed.checksum == source.checksum);
        assert(source.a == 11);
        destroy!false(*placed);

        placed = localBlitCopy(target, source);
        assert(placed is target);
        assert(placed.checksum == source.checksum);
        assert(source.a == 11);
        destroy!false(*placed);
    }

    // Explicit copy constructor.
    {
        align(CopyCtorValue.alignof)
            ubyte[CopyCtorValue.sizeof] raw = void;
        auto target = rawTarget!CopyCtorValue(raw);
        auto source = CopyCtorValue(17);

        CopyCtorValue.copies = 0;
        auto placed = copyEmplaceCopy(target, source);
        assert(placed.value == 17);
        assert(source.value == 17);
        assert(CopyCtorValue.copies == 1);
        destroy!false(*placed);

        CopyCtorValue.copies = 0;
        placed = emplaceCopy(target, source);
        assert(placed.value == 17);
        assert(CopyCtorValue.copies == 1);
        destroy!false(*placed);
    }

    // Legacy postblit.
    {
        align(PostblitValue.alignof)
            ubyte[PostblitValue.sizeof] raw = void;
        auto target = rawTarget!PostblitValue(raw);
        PostblitValue source;
        source.value = 23;

        PostblitValue.postblits = 0;
        auto placed = copyEmplaceCopy(target, source);
        assert(placed.value == 23);
        assert(PostblitValue.postblits == 1);
        destroy!false(*placed);

        PostblitValue.postblits = 0;
        placed = emplaceCopy(target, source);
        assert(placed.value == 23);
        assert(PostblitValue.postblits == 1);
        destroy!false(*placed);
    }

    // Disabled default initialization plus explicit copy constructor.
    {
        align(DisabledInitCopy.alignof)
            ubyte[DisabledInitCopy.sizeof] raw = void;
        auto target = rawTarget!DisabledInitCopy(raw);
        auto source = DisabledInitCopy(31);

        DisabledInitCopy.copies = 0;
        auto placed = copyEmplaceCopy(target, source);
        assert(placed.value == 31);
        assert(DisabledInitCopy.copies == 1);
        destroy!false(*placed);

        DisabledInitCopy.copies = 0;
        placed = emplaceCopy(target, source);
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
extern(C) ulong bench_copyemplace(
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
            auto placed = copyEmplaceCopy(target, values[i]);
            checksum += placed.checksum;
            destroy!false(*placed);
            ++i;
        }
        ++round;
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_localblit(
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
            auto placed = localBlitCopy(target, values[i]);
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
            "usage: element-lifetime-copy-probe <emplace|copyemplace|localblit> <rounds>");
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
        case "copyemplace":
            checksum = bench_copyemplace(values.ptr, values.length, rounds);
            break;
        case "localblit":
            checksum = bench_localblit(values.ptr, values.length, rounds);
            break;
    }

    writeln(args[1], " ", checksum);
}
