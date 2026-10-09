module app;

import containers :
    RingBuffer,
    ScratchBuffer,
    StaticRingBuffer,
    StaticVector;
import std.traits : hasIndirections, isNested;

void main()
{
    int outer;

    struct Nested
    {
        int value;

        int contextValue() const
        {
            return outer;
        }
    }

    static assert(isNested!Nested);
    static assert(hasIndirections!Nested);

    static assert(!__traits(compiles, {
        StaticRingBuffer!(Nested, 2) value;
    }));
    static assert(!__traits(compiles, {
        StaticVector!(Nested, 2) value;
    }));
    static assert(!__traits(compiles, {
        auto value = RingBuffer!Nested(2);
    }));
    static assert(!__traits(compiles, {
        auto value = ScratchBuffer!Nested(2);
    }));

    // Declaration location alone is not the restriction. A function-local
    // value type without hidden context remains an ordinary admissible T.
    struct PlainLocal
    {
        int value;
    }

    static assert(!isNested!PlainLocal);
    static assert(!hasIndirections!PlainLocal);

    PlainLocal seed;
    seed.value = 7;

    StaticRingBuffer!(PlainLocal, 2) fixedRing;
    assert(fixedRing.tryPushBack(seed));
    assert(fixedRing.front.value == 7);

    StaticVector!(PlainLocal, 2) vector;
    vector.pushBack(seed);
    assert(vector.front.value == 7);

    auto runtimeRing = RingBuffer!PlainLocal(2);
    assert(runtimeRing.tryPushBack(seed));
    assert(runtimeRing.front.value == 7);

    auto scratch = ScratchBuffer!PlainLocal(2);
    assert(scratch.tryPushBack(seed));
    assert(scratch[0].value == 7);
}
