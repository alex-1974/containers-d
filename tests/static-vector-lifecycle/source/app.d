module app;

import containers : StaticRingBuffer;
import containers.static_vector : StaticVector;
import std.stdio : stderr;

private struct CopyTracked
{
    static int alive;
    static int copies;
    static int destroyed;

    int value;

    this(int value)
    {
        this.value = value;
        ++alive;
    }

    this(ref return scope CopyTracked rhs)
    {
        value = rhs.value;
        ++alive;
        ++copies;
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
    long value;
}

private struct OverAlignedHolder
{
    ubyte prefix;
    StaticVector!(OverAligned, 3) vector;
}

private void testCopyConstruction()
{
    CopyTracked.alive = 0;
    CopyTracked.copies = 0;
    CopyTracked.destroyed = 0;

    {
        auto first = CopyTracked(11);
        auto second = CopyTracked(22);

        StaticVector!(CopyTracked, 3) original;
        original.pushBack(first);
        original.pushBack(second);

        const copiesBeforeVectorCopy =
            CopyTracked.copies;

        auto copied = original;

        assert(copied.length == original.length);
        assert(CopyTracked.copies ==
            copiesBeforeVectorCopy + original.length);

        assert(&copied[0] !is &original[0]);
        assert(&copied[1] !is &original[1]);

        assert(copied[0].value == 11);
        assert(copied[1].value == 22);

        copied[0].value = 99;
        assert(original[0].value == 11);
        assert(copied[0].value == 99);

        copied.popBack();
        assert(copied.length == 1);
        assert(original.length == 2);

        copied.clear();
        assert(copied.empty);
        assert(original.length == 2);
    }

    assert(CopyTracked.alive == 0);
    assert(CopyTracked.destroyed > 0);
}

private void testRingMoveOnlySelfReference()
{
    SelfReferentialMove.moves = 0;

    StaticRingBuffer!(SelfReferentialMove, 2) source;

    auto seed = SelfReferentialMove(41);
    assert(source.tryPushBack(__rvalue(seed)));
    assert(source.front.valid);
    assert(SelfReferentialMove.moves >= 1);

    const movesBeforeContainerMove =
        SelfReferentialMove.moves;

    auto moved = __rvalue(source);

    assert(source.empty);
    assert(moved.length == 1);
    assert(SelfReferentialMove.moves >
        movesBeforeContainerMove);

    if (!moved.front.valid)
    {
        stderr.writefln(
            "StaticRingBuffer self-ref mismatch: value@%s self=%s",
            cast(void*) &moved.front.value,
            cast(void*) moved.front.self);
    }

    assert(moved.front.valid);
}

private void testLanguageMoveAndFinalAddress()
{
    SelfReferentialMove.moves = 0;

    StaticVector!(SelfReferentialMove, 2) source;

    auto seed = SelfReferentialMove(73);
    source.pushBack(__rvalue(seed));

    assert(source.length == 1);
    assert(source[0].value == 73);
    assert(source[0].valid);
    assert(SelfReferentialMove.moves >= 1);

    // The exact readable state of an already-moved source object is not part
    // of the container contract. What matters is that T's move constructor
    // ran and the stored object is valid at its final slot address.
    const movesBeforeContainerMove =
        SelfReferentialMove.moves;

    auto moved = __rvalue(source);

    assert(source.empty);
    assert(moved.length == 1);
    assert(SelfReferentialMove.moves >
        movesBeforeContainerMove);
    assert(moved[0].value == 73);

    if (!moved[0].valid)
    {
        stderr.writefln(
            "StaticVector self-ref mismatch: value@%s self=%s",
            cast(void*) &moved[0].value,
            cast(void*) moved[0].self);
    }

    assert(moved[0].valid);

    moved.clear();
    assert(moved.empty);
}

private void testOverAlignmentWhenEmbedded()
{
    OverAlignedHolder holder;

    holder.vector.pushBack(OverAligned(7));
    holder.vector.pushBack(OverAligned(9));

    foreach (index; 0 .. holder.vector.length)
    {
        const address =
            cast(size_t) &holder.vector[index];

        assert(address % OverAligned.alignof == 0);
    }

    assert(holder.vector[0].value == 7);
    assert(holder.vector[1].value == 9);
}

void main()
{
    testCopyConstruction();
    testRingMoveOnlySelfReference();
    testLanguageMoveAndFinalAddress();
    testOverAlignmentWhenEmbedded();
}
