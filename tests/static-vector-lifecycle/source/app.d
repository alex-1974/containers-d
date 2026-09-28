module app;

import containers.static_vector : StaticVector;

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

private void testLanguageMoveAndFinalAddress()
{
    StaticVector!(SelfReferentialMove, 2) source;

    auto seed = SelfReferentialMove(73);
    source.pushBack(__rvalue(seed));

    assert(source.length == 1);
    assert(source[0].value == 73);
    assert(source[0].valid);
    assert(seed.value == -1);
    assert(seed.self is null);

    auto moved = __rvalue(source);

    assert(source.empty);
    assert(moved.length == 1);
    assert(moved[0].value == 73);
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
    testLanguageMoveAndFinalAddress();
    testOverAlignmentWhenEmbedded();
}
