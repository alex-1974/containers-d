module app;

import containers.research.scratch_buffer : ResearchScratchBuffer;

private void exerciseReuse() @safe @nogc nothrow
{
    auto scratch = ResearchScratchBuffer!int(8);

    const initialCapacity = scratch.capacity;

    foreach (cycle; 0 .. 64)
    {
        scratch.reset();

        foreach (i; 0 .. initialCapacity)
            assert(scratch.tryPushBack(cast(int)(cycle + i)));

        assert(scratch.full);
        assert(!scratch.tryPushBack(-1));
        assert(scratch.length == initialCapacity);
        assert(scratch.highWater == initialCapacity);

        auto live = scratch[];
        assert(live.length == initialCapacity);

        foreach (i, value; live)
            assert(value == cast(int)(cycle + i));
    }

    scratch.reset();
    assert(scratch.empty);
    assert(scratch.capacity == initialCapacity);
    assert(scratch.highWater == initialCapacity);
}

void main()
{
    exerciseReuse();
}
