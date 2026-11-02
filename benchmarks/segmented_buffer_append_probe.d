module containers.segmented_buffer_append_probe;

import containers : SegmentedByteBuffer;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t segmentSize = 4096;
enum size_t maximumLength = 1_048_576;

private ulong mix(ulong state, ubyte value) @safe @nogc nothrow
{
    return (state ^ value) * 0x100000001B3UL;
}

pragma(inline, false)
extern(C) ulong bench_segmented(
    ref SegmentedByteBuffer buffer,
    scope const(ubyte)[] input,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (round; 0 .. rounds)
    {
        buffer.reset();
        const accepted = buffer.append(input);
        assert(accepted == input.length);
        assert(buffer.length == input.length);
        assert(buffer.segmentCount != 0);

        foreach (index; 0 .. buffer.segmentCount())
            foreach (value; buffer.segment(index))
                checksum = mix(checksum, value ^ cast(ubyte) round);
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_manual_segments(
    scope ubyte[][] segments,
    scope const(ubyte)[] input,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;
    const perSegment = segments[0].length;

    foreach (round; 0 .. rounds)
    {
        foreach (segmentIndex, segment; segments)
        {
            const begin = segmentIndex * perSegment;
            const count = (input.length - begin) < perSegment
                ? input.length - begin : perSegment;
            if (count != 0)
                segment[0 .. count] = input[begin .. begin + count];
        }

        foreach (segmentIndex, segment; segments)
        {
            const begin = segmentIndex * perSegment;
            const count = (input.length - begin) < perSegment
                ? input.length - begin : perSegment;
            foreach (value; segment[0 .. count])
                checksum = mix(checksum, value ^ cast(ubyte) round);
        }
    }
    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_flattened(
    scope ubyte[] storage,
    scope const(ubyte)[] input,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;
    foreach (round; 0 .. rounds)
    {
        storage[] = input[];
        foreach (value; storage)
            checksum = mix(checksum, value ^ cast(ubyte) round);
    }
    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: segmented-buffer-append-probe " ~
            "<candidate|manual|flatten> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);
    ubyte[maximumLength] input;
    foreach (i, ref value; input)
        value = cast(ubyte) (i * 17 + 3);

    final switch (args[1])
    {
        case "candidate":
            auto buffer = SegmentedByteBuffer(segmentSize, maximumLength);
            writeln("candidate ",
                bench_segmented(buffer, input[], rounds));
            break;
        case "manual":
            ubyte[][] segments;
            foreach (i; 0 .. (maximumLength + segmentSize - 1) / segmentSize)
                segments ~= new ubyte[segmentSize];
            writeln("manual ",
                bench_manual_segments(segments, input[], rounds));
            break;
        case "flatten":
            auto storage = new ubyte[maximumLength];
            writeln("flatten ",
                bench_flattened(storage, input[], rounds));
            break;
    }
}
