module m8_local_capture_probe;

import std.stdio : stdout, writeln;

version (TraitsProbe)
{
    void main()
    {
        int context = 101;

        struct LocalValue
        {
            int value;

            this(int value)
            {
                this.value = value;
            }

            this(return scope LocalValue rhs)
            {
                value = rhs.value;
                rhs.value = -1;
            }

            int contextValue() const
            {
                return context;
            }
        }

        LocalValue value;

        writeln(
            "isNested=", __traits(isNested, LocalValue),
            " constructCompiles=", __traits(compiles, LocalValue(1)),
            " initCompiles=", __traits(compiles, LocalValue.init),
            " sizeof=", LocalValue.sizeof,
            " alignof=", LocalValue.alignof,
            " context=", value.contextValue);
    }
}
else version (OrdinaryMoveProbe)
{
    void main()
    {
        int context = 102;

        struct LocalValue
        {
            int value;

            this(int value)
            {
                this.value = value;
            }

            this(return scope LocalValue rhs)
            {
                value = rhs.value;
                rhs.value = -1;
            }

            int contextValue() const
            {
                return context;
            }
        }

        auto source = LocalValue(31);
        LocalValue target = __rvalue(source);

        writeln(
            "isNested=", __traits(isNested, LocalValue),
            " source.value=", source.value,
            " target.value=", target.value,
            " target.context=", target.contextValue);
    }
}
else version (PlacementMoveProbe)
{
    void main()
    {
        int context = 103;

        struct LocalValue
        {
            int value;

            this(int value)
            {
                this.value = value;
            }

            this(return scope LocalValue rhs)
            {
                value = rhs.value;
                rhs.value = -1;
            }

            int contextValue() const
            {
                return context;
            }
        }

        align(LocalValue.alignof) ubyte[LocalValue.sizeof] storage = void;
        auto target = cast(LocalValue*) storage.ptr;

        auto source = LocalValue(32);
        auto placed = new (*target) LocalValue(__rvalue(source));

        writeln(
            "isNested=", __traits(isNested, LocalValue),
            " source.value=", source.value,
            " target.value=", placed.value,
            " target.context=", placed.contextValue,
            " same-address=", placed is target);

        stdout.flush();
        destroy!false(*placed);
    }
}
else
{
    static assert(0, "select one probe mode");
}
