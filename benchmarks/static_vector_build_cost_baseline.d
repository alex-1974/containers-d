module static_vector_build_cost_baseline;


private ulong foldValue(ulong checksum, ulong value)
    pure nothrow @safe @nogc
{
    checksum ^= value + 0x9E37_79B9_7F4A_7C15UL;
    checksum *= 0x0000_0100_0000_01B3UL;
    return checksum;
}


private struct BaselineVector(size_t Capacity)
if (Capacity > 0)
{
    ulong[Capacity] data;
    size_t length;

    void pushBack(ulong value)
        pure nothrow @safe @nogc
    {
        assert(length < Capacity);
        data[length] = value;
        ++length;
    }

    ulong opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        assert(index < length);
        return data[index];
    }
}

private ulong run(size_t Capacity)(ulong seed)
    pure nothrow @safe @nogc
{
    BaselineVector!Capacity vector;

    static foreach (i; 0 .. Capacity)
        vector.pushBack(seed + i);

    ulong checksum = 0xCBF2_9CE4_8422_2325UL;

    static foreach (i; 0 .. Capacity)
        checksum = foldValue(checksum, vector[i]);

    return checksum;
}

extern(C) ulong baseline_1(ulong x) { return run!1(x); }
extern(C) ulong baseline_2(ulong x) { return run!2(x); }
extern(C) ulong baseline_3(ulong x) { return run!3(x); }
extern(C) ulong baseline_4(ulong x) { return run!4(x); }
extern(C) ulong baseline_8(ulong x) { return run!8(x); }
extern(C) ulong baseline_16(ulong x) { return run!16(x); }
extern(C) ulong baseline_32(ulong x) { return run!32(x); }
extern(C) ulong baseline_64(ulong x) { return run!64(x); }
