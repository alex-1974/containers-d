module app;

import containers : ScratchBuffer;

private struct Tracked
{
    static int alive;
    static int destroyed;

    int value;

    this(int value)
    {
        this.value = value;
        ++alive;
    }

    this(ref return scope Tracked rhs)
    {
        value = rhs.value;
        ++alive;
    }

    ~this()
    {
        --alive;
        ++destroyed;
    }
}

private struct SelfReferentialMove
{
    static int moves;

    int value;
    int* self;

    this(int value) @system @nogc nothrow
    {
        this.value = value;
        self = &this.value;
    }

    @disable this(ref return scope SelfReferentialMove rhs);

    this(return scope SelfReferentialMove rhs) @system @nogc nothrow
    {
        value = rhs.value;
        self = &this.value;
        rhs.value = -1;
        rhs.self = null;
        ++moves;
    }

    bool valid() @safe @nogc nothrow
    {
        return self is &value;
    }
}

align(64) private struct OverAligned
{
    ulong value;
}

private void testResetLifetime()
{
    Tracked.alive = 0;
    Tracked.destroyed = 0;

    {
        auto seed = Tracked(11);
        auto scratch = ScratchBuffer!Tracked(3);

        assert(scratch.tryPushBack(seed));
        assert(scratch.tryPushBack(seed));
        assert(Tracked.alive == 3);

        scratch.reset();

        assert(scratch.empty);
        assert(scratch.capacity == 3);
        assert(Tracked.alive == 1);
        assert(Tracked.destroyed == 2);
    }

    assert(Tracked.alive == 0);
}

private void testWholeOwnerMoveDoesNotRelocateElements()
{
    SelfReferentialMove.moves = 0;

    auto scratch = ScratchBuffer!SelfReferentialMove(2);
    auto seed = SelfReferentialMove(73);

    assert(scratch.tryPushBack(__rvalue(seed)));
    assert(scratch[0].valid);

    const movesBeforeOwnerMove = SelfReferentialMove.moves;
    const elementAddressBefore = &scratch[0];

    auto moved = __rvalue(scratch);

    assert(scratch.capacity == 0);
    assert(scratch.empty);

    assert(moved.length == 1);
    assert(&moved[0] is elementAddressBefore);
    assert(moved[0].valid);
    assert(SelfReferentialMove.moves == movesBeforeOwnerMove);

    moved.reset();
}

private void testOverAlignedReserve()
{
    ScratchBuffer!OverAligned scratch;

    assert(scratch.tryReserve(2));
    assert(scratch.tryPushBack(OverAligned(7)));

    assert(
        cast(size_t) &scratch[0] %
        OverAligned.alignof == 0);

    scratch.reset();

    assert(scratch.tryReserve(5));
    assert(scratch.tryPushBack(OverAligned(9)));

    assert(
        cast(size_t) &scratch[0] %
        OverAligned.alignof == 0);
}

void main()
{
    testResetLifetime();
    testWholeOwnerMoveDoesNotRelocateElements();
    testOverAlignedReserve();
}
