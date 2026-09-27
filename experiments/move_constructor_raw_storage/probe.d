module move_constructor_raw_storage_probe;

import core.lifetime : emplace, moveEmplace;
import std.stdio : writeln;

struct Counters
{
    int copies;
    int moves;
    int destructs;
}

struct MoveAware
{
    static Counters counts;

    int value;
    bool armed;

    this(int value)
    {
        this.value = value;
        armed = true;
    }

    this(ref return scope MoveAware rhs)
    {
        value = rhs.value;
        armed = rhs.armed;
        ++counts.copies;
    }

    this(return scope MoveAware rhs)
    {
        value = rhs.value;
        armed = rhs.armed;
        rhs.value = -1;
        rhs.armed = false;
        ++counts.moves;
    }

    ~this()
    {
        ++counts.destructs;
    }
}

struct SelfAware
{
    static Counters counts;

    int value;
    int* self;

    this(int value)
    {
        this.value = value;
        self = &this.value;
    }

    this(ref return scope SelfAware rhs)
    {
        value = rhs.value;
        self = &this.value;
        ++counts.copies;
    }

    this(return scope SelfAware rhs)
    {
        value = rhs.value;
        self = &this.value;
        rhs.self = null;
        rhs.value = -1;
        ++counts.moves;
    }

    ~this()
    {
        ++counts.destructs;
    }

    bool selfValid() @safe nothrow @nogc
    {
        return self is &value;
    }
}

struct PostMoveAware
{
    static int postMoves;

    int value;
    int* self;

    this(int value)
    {
        this.value = value;
        self = &this.value;
    }

    @disable this(ref return scope PostMoveAware rhs);

    void opPostMove(const ref PostMoveAware old) @safe nothrow @nogc
    {
        self = &value;
        ++postMoves;
    }

    bool selfValid() @safe nothrow @nogc
    {
        return self is &value;
    }
}

private T* rawSlot(T)(ref ubyte[T.sizeof] storage) @trusted
{
    return cast(T*) storage.ptr;
}

private void resetMoveAware()
{
    MoveAware.counts = Counters.init;
}

private void resetSelfAware()
{
    SelfAware.counts = Counters.init;
}

private void probeDirectLanguageMove()
{
    resetMoveAware();

    {
        auto source = MoveAware(11);
        MoveAware target = __rvalue(source);

        writeln(
            "direct-language-move",
            " moves=", MoveAware.counts.moves,
            " copies=", MoveAware.counts.copies,
            " source.value=", source.value,
            " source.armed=", source.armed,
            " target.value=", target.value,
            " target.armed=", target.armed);
    }

    writeln("direct-language-move destructs=", MoveAware.counts.destructs);
}

private void probeEmplaceRvalue()
{
    resetMoveAware();

    align(MoveAware.alignof) ubyte[MoveAware.sizeof] storage = void;
    auto target = rawSlot!MoveAware(storage);

    {
        auto source = MoveAware(21);

        emplace(target, __rvalue(source));

        writeln(
            "emplace-rvalue",
            " moves=", MoveAware.counts.moves,
            " copies=", MoveAware.counts.copies,
            " source.value=", source.value,
            " source.armed=", source.armed,
            " target.value=", target.value,
            " target.armed=", target.armed);

        destroy!false(*target);
    }

    writeln("emplace-rvalue destructs=", MoveAware.counts.destructs);
}

private void probeMoveEmplace()
{
    resetMoveAware();

    align(MoveAware.alignof) ubyte[MoveAware.sizeof] storage = void;
    auto target = rawSlot!MoveAware(storage);

    {
        auto source = MoveAware(31);

        moveEmplace(source, *target);

        writeln(
            "moveEmplace-move-aware",
            " moves=", MoveAware.counts.moves,
            " copies=", MoveAware.counts.copies,
            " source.value=", source.value,
            " source.armed=", source.armed,
            " target.value=", target.value,
            " target.armed=", target.armed);

        destroy!false(*target);
    }

    writeln("moveEmplace-move-aware destructs=", MoveAware.counts.destructs);
}

private void probeSelfAware()
{
    resetSelfAware();

    align(SelfAware.alignof) ubyte[SelfAware.sizeof] emplaceStorage = void;
    align(SelfAware.alignof) ubyte[SelfAware.sizeof] moveStorage = void;

    auto emplaced = rawSlot!SelfAware(emplaceStorage);
    auto relocated = rawSlot!SelfAware(moveStorage);

    {
        auto source = SelfAware(41);
        assert(source.selfValid);

        emplace(emplaced, __rvalue(source));

        writeln(
            "self-aware-emplace",
            " moves=", SelfAware.counts.moves,
            " copies=", SelfAware.counts.copies,
            " source.self-null=", source.self is null,
            " target.self-valid=", emplaced.selfValid);

        destroy!false(*emplaced);
    }

    {
        auto source = SelfAware(42);
        assert(source.selfValid);

        moveEmplace(source, *relocated);

        writeln(
            "self-aware-moveEmplace",
            " moves=", SelfAware.counts.moves,
            " copies=", SelfAware.counts.copies,
            " source.self-null=", source.self is null,
            " target.self-valid=", relocated.selfValid,
            " target.self-points-source=", relocated.self is &source.value);

        destroy!false(*relocated);
    }

    writeln("self-aware destructs=", SelfAware.counts.destructs);
}

private void probePostMoveAware()
{
    PostMoveAware.postMoves = 0;

    align(PostMoveAware.alignof) ubyte[PostMoveAware.sizeof] storage = void;
    auto target = rawSlot!PostMoveAware(storage);

    auto source = PostMoveAware(51);
    assert(source.selfValid);

    moveEmplace(source, *target);

    writeln(
        "post-move-aware",
        " opPostMove=", PostMoveAware.postMoves,
        " target.self-valid=", target.selfValid,
        " target.value=", target.value);

    destroy!false(*target);
}

void main()
{
    writeln("hasMoveConstructor MoveAware=", __traits(hasMoveConstructor, MoveAware));
    writeln("hasMoveConstructor SelfAware=", __traits(hasMoveConstructor, SelfAware));
    writeln("hasMoveConstructor PostMoveAware=", __traits(hasMoveConstructor, PostMoveAware));

    probeDirectLanguageMove();
    probeEmplaceRvalue();
    probeMoveEmplace();
    probeSelfAware();
    probePostMoveAware();
}
