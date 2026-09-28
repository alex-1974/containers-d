module containers.dmd_codegen_probe;

import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t valueCount = 16;
enum size_t indexCount = 256;

private struct Value { ulong value; }

private ulong slotValue(size_t index) @safe @nogc nothrow
{
    return (cast(ulong) index + 1) * 0x9E37_79B9_7F4A_7C15UL ^
        0xD6E8_FEB8_6659_FD93UL;
}

private void fillValues(ref Value[valueCount] values) @safe @nogc nothrow
{
    foreach (i, ref value; values)
        value.value = slotValue(i);
}

private void fillIndices(ref ubyte[indexCount] indices) @safe @nogc nothrow
{
    ulong state = 0xA076_1D64_78BD_642FUL;
    foreach (i, ref index; indices)
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        index = cast(ubyte)((state ^ cast(ulong)i) & (valueCount - 1));
    }
}

pragma(inline, false)
extern(C) ulong bench_foreach_struct(
    const(Value)* base, const(ubyte)* indices,
    size_t count, size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    foreach (_; 0 .. rounds)
        foreach (i; 0 .. count)
            checksum += base[indices[i]].value;
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_while_struct(
    const(Value)* base, const(ubyte)* indices,
    size_t count, size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        size_t i;
        while (i < count)
        {
            checksum += base[indices[i]].value;
            ++i;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_while_scalar(
    const(ulong)* base, const(ubyte)* indices,
    size_t count, size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        size_t i;
        while (i < count)
        {
            checksum += base[indices[i]];
            ++i;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_pointer_indices(
    const(ulong)* base, const(ubyte)* indices,
    size_t count, size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        auto cursor = indices;
        const end = indices + count;
        while (cursor != end)
        {
            checksum += base[*cursor];
            ++cursor;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_unrolled_pointer4(
    const(ulong)* base, const(ubyte)* indices,
    size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        auto cursor = indices;
        const end = indices + indexCount;
        while (cursor != end)
        {
            checksum += base[cursor[0]];
            checksum += base[cursor[1]];
            checksum += base[cursor[2]];
            checksum += base[cursor[3]];
            cursor += 4;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_size_pointer4(
    const(ulong)* base, const(size_t)* indices,
    size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        auto cursor = indices;
        const end = indices + indexCount;
        while (cursor != end)
        {
            checksum += base[cursor[0]];
            checksum += base[cursor[1]];
            checksum += base[cursor[2]];
            checksum += base[cursor[3]];
            cursor += 4;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_size_pointer8(
    const(ulong)* base, const(size_t)* indices,
    size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        auto cursor = indices;
        const end = indices + indexCount;
        while (cursor != end)
        {
            checksum += base[cursor[0]];
            checksum += base[cursor[1]];
            checksum += base[cursor[2]];
            checksum += base[cursor[3]];
            checksum += base[cursor[4]];
            checksum += base[cursor[5]];
            checksum += base[cursor[6]];
            checksum += base[cursor[7]];
            cursor += 8;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_size_indices(
    const(ulong)* base, const(size_t)* indices,
    size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        size_t i;
        while (i < indexCount)
        {
            checksum += base[indices[i]];
            ++i;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_size_unrolled4(
    const(ulong)* base, const(size_t)* indices,
    size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        size_t i;
        while (i < indexCount)
        {
            checksum += base[indices[i]];
            checksum += base[indices[i + 1]];
            checksum += base[indices[i + 2]];
            checksum += base[indices[i + 3]];
            i += 4;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_fixed_count(
    const(ulong)* base, const(ubyte)* indices,
    size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        size_t i;
        while (i < indexCount)
        {
            checksum += base[indices[i]];
            ++i;
        }
        ++round;
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_unrolled4(
    const(ulong)* base, const(ubyte)* indices,
    size_t rounds) @system @nogc nothrow
{
    ulong checksum;
    size_t round;
    while (round < rounds)
    {
        size_t i;
        while (i < indexCount)
        {
            checksum += base[indices[i]];
            checksum += base[indices[i + 1]];
            checksum += base[indices[i + 2]];
            checksum += base[indices[i + 3]];
            i += 4;
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
            "usage: dmd-codegen-probe " ~
            "<foreach-struct|while-struct|while-scalar|pointer-indices|" ~
            "unrolled-pointer4|size-pointer4|size-pointer8|" ~
            "size-indices|size-unrolled4|" ~
            "fixed-count|unrolled4> <rounds>");
        return;
    }

    Value[valueCount] values = void;
    ubyte[indexCount] indices = void;
    size_t[indexCount] sizeIndices = void;
    fillValues(values);
    fillIndices(indices);

    foreach (i, index; indices)
        sizeIndices[i] = index;

    const rounds = to!size_t(args[2]);
    const scalarBase = cast(const(ulong)*)values.ptr;
    ulong checksum;

    final switch (args[1])
    {
        case "foreach-struct":
            checksum = bench_foreach_struct(
                values.ptr, indices.ptr, indices.length, rounds);
            break;
        case "while-struct":
            checksum = bench_while_struct(
                values.ptr, indices.ptr, indices.length, rounds);
            break;
        case "while-scalar":
            checksum = bench_while_scalar(
                scalarBase, indices.ptr, indices.length, rounds);
            break;
        case "pointer-indices":
            checksum = bench_pointer_indices(
                scalarBase, indices.ptr, indices.length, rounds);
            break;
        case "unrolled-pointer4":
            checksum = bench_unrolled_pointer4(
                scalarBase, indices.ptr, rounds);
            break;
        case "size-pointer4":
            checksum = bench_size_pointer4(
                scalarBase, sizeIndices.ptr, rounds);
            break;
        case "size-pointer8":
            checksum = bench_size_pointer8(
                scalarBase, sizeIndices.ptr, rounds);
            break;
        case "size-indices":
            checksum = bench_size_indices(
                scalarBase, sizeIndices.ptr, rounds);
            break;
        case "size-unrolled4":
            checksum = bench_size_unrolled4(
                scalarBase, sizeIndices.ptr, rounds);
            break;
        case "fixed-count":
            checksum = bench_fixed_count(
                scalarBase, indices.ptr, rounds);
            break;
        case "unrolled4":
            checksum = bench_unrolled4(
                scalarBase, indices.ptr, rounds);
            break;
    }

    writeln(args[1], " ", checksum);
}
