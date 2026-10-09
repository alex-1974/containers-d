module emplace_language_move_probe;

import core.lifetime : destroy, emplace, forward;

struct MoveAware
{
    static int moves;

    int value;
    bool armed;

    this(int value)
    {
        this.value = value;
        armed = true;
    }

    this(return scope MoveAware rhs)
    {
        value = rhs.value;
        armed = rhs.armed;
        rhs.value = -1;
        rhs.armed = false;
        ++moves;
    }
}

struct MoveAwareDtor
{
    static int moves;

    int value;
    bool armed;

    this(int value)
    {
        this.value = value;
        armed = true;
    }

    this(return scope MoveAwareDtor rhs)
    {
        value = rhs.value;
        armed = rhs.armed;
        rhs.value = -1;
        rhs.armed = false;
        ++moves;
    }

    ~this() {}
}

struct SelfAware
{
    static int moves;

    int value;
    int* self;

    this(int value)
    {
        this.value = value;
        self = &this.value;
    }

    this(return scope SelfAware rhs)
    {
        value = rhs.value;
        self = &this.value;
        rhs.value = -1;
        rhs.self = null;
        ++moves;
    }

    bool selfValid() const @safe nothrow @nogc
    {
        return self is &value;
    }
}

private T* rawSlot(T)(ref ubyte[T.sizeof] storage) @trusted
{
    return cast(T*) storage.ptr;
}

private void forwardAssign(T)(ref T target, auto ref T value)
{
    target = forward!value;
}

private void directMove()
{
    MoveAware.moves = 0;
    auto source = MoveAware(11);
    MoveAware target = __rvalue(source);

    import std.stdio : writeln;
    writeln("direct",
        " moves=", MoveAware.moves,
        " source.value=", source.value,
        " source.armed=", source.armed,
        " target.value=", target.value,
        " target.armed=", target.armed);
}

private void assignmentMirror()
{
    MoveAware.moves = 0;
    auto source = MoveAware(21);
    MoveAware target;
    forwardAssign(target, __rvalue(source));

    import std.stdio : writeln;
    writeln("forward-assign",
        " moves=", MoveAware.moves,
        " source.value=", source.value,
        " source.armed=", source.armed,
        " target.value=", target.value,
        " target.armed=", target.armed);
}

private void emplaceNoDestructor()
{
    MoveAware.moves = 0;
    align(MoveAware.alignof) ubyte[MoveAware.sizeof] storage = void;
    auto target = rawSlot!MoveAware(storage);
    auto source = MoveAware(31);

    emplace(target, __rvalue(source));

    import std.stdio : writeln;
    writeln("emplace-no-dtor",
        " moves=", MoveAware.moves,
        " source.value=", source.value,
        " source.armed=", source.armed,
        " target.value=", target.value,
        " target.armed=", target.armed);

    destroy!false(*target);
}

private void emplaceWithDestructor()
{
    MoveAwareDtor.moves = 0;
    align(MoveAwareDtor.alignof) ubyte[MoveAwareDtor.sizeof] storage = void;
    auto target = rawSlot!MoveAwareDtor(storage);
    auto source = MoveAwareDtor(41);

    emplace(target, __rvalue(source));

    import std.stdio : writeln;
    writeln("emplace-dtor",
        " moves=", MoveAwareDtor.moves,
        " source.value=", source.value,
        " source.armed=", source.armed,
        " target.value=", target.value,
        " target.armed=", target.armed);

    destroy!false(*target);
}

private void emplaceSelfAware()
{
    SelfAware.moves = 0;
    align(SelfAware.alignof) ubyte[SelfAware.sizeof] storage = void;
    auto target = rawSlot!SelfAware(storage);
    auto source = SelfAware(51);

    assert(source.selfValid);
    emplace(target, __rvalue(source));

    import std.stdio : writeln;
    writeln("emplace-self",
        " moves=", SelfAware.moves,
        " source.value=", source.value,
        " source.self-null=", source.self is null,
        " target.value=", target.value,
        " target.self-valid=", target.selfValid,
        " target.self-points-source=", target.self is &source.value);

    destroy!false(*target);
}

void main()
{
    import std.stdio : writeln;

    writeln("hasMoveConstructor MoveAware=",
        __traits(hasMoveConstructor, MoveAware));
    writeln("hasMoveConstructor MoveAwareDtor=",
        __traits(hasMoveConstructor, MoveAwareDtor));
    writeln("hasMoveConstructor SelfAware=",
        __traits(hasMoveConstructor, SelfAware));

    directMove();
    assignmentMirror();
    emplaceNoDestructor();
    emplaceWithDestructor();
    emplaceSelfAware();
}
