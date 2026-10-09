module m8_module_scope_probe;

import std.stdio : stdout, writeln;

struct ModuleValue
{
    int value;

    this(int value)
    {
        this.value = value;
    }

    this(return scope ModuleValue rhs)
    {
        value = rhs.value;
        rhs.value = -1;
    }
}

version (TraitsProbe)
{
    void main()
    {
        writeln(
            "isNested=", __traits(isNested, ModuleValue),
            " constructCompiles=", __traits(compiles, ModuleValue(1)),
            " initCompiles=", __traits(compiles, ModuleValue.init),
            " sizeof=", ModuleValue.sizeof,
            " alignof=", ModuleValue.alignof);
    }
}
else version (OrdinaryMoveProbe)
{
    void main()
    {
        auto source = ModuleValue(11);
        ModuleValue target = __rvalue(source);

        writeln(
            "source.value=", source.value,
            " target.value=", target.value);
    }
}
else version (PlacementMoveProbe)
{
    void main()
    {
        align(ModuleValue.alignof) ubyte[ModuleValue.sizeof] storage = void;
        auto target = cast(ModuleValue*) storage.ptr;

        auto source = ModuleValue(12);
        auto placed = new (*target) ModuleValue(__rvalue(source));

        writeln(
            "source.value=", source.value,
            " target.value=", placed.value,
            " same-address=", placed is target);

        stdout.flush();
        destroy!false(*placed);
    }
}
else
{
    static assert(0, "select one probe mode");
}
