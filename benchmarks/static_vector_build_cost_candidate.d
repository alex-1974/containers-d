module static_vector_build_cost_candidate;

import containers.static_vector : StaticVector;


private ulong foldValue(ulong checksum, ulong value)
    pure nothrow @safe @nogc
{
    checksum ^= value + 0x9E37_79B9_7F4A_7C15UL;
    checksum *= 0x0000_0100_0000_01B3UL;
    return checksum;
}


private ulong run(size_t Capacity)(ulong seed)
    pure nothrow @safe @nogc
{
    StaticVector!(ulong, Capacity) vector;

    static foreach (i; 0 .. Capacity)
        vector.pushBack(seed + i);

    ulong checksum = 0xCBF2_9CE4_8422_2325UL;

    static foreach (i; 0 .. Capacity)
        checksum = foldValue(checksum, vector[i]);

    return checksum;
}

extern(C) ulong candidate_1(ulong x) { return run!1(x); }
extern(C) ulong candidate_2(ulong x) { return run!2(x); }
extern(C) ulong candidate_3(ulong x) { return run!3(x); }
extern(C) ulong candidate_4(ulong x) { return run!4(x); }
extern(C) ulong candidate_8(ulong x) { return run!8(x); }
extern(C) ulong candidate_16(ulong x) { return run!16(x); }
extern(C) ulong candidate_32(ulong x) { return run!32(x); }
extern(C) ulong candidate_64(ulong x) { return run!64(x); }
