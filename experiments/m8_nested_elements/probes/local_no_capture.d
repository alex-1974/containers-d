module m8_local_no_capture_probe;

import std.stdio : writeln;

version (TraitsProbe)
{
    void main()
    {
        struct LocalValue
        {
            int value;
        }

        writeln(
            "isNested=", __traits(isNested, LocalValue),
            " sizeof=", LocalValue.sizeof,
            " alignof=", LocalValue.alignof);
    }
}
else version (OrdinaryMoveProbe)
{
    void main()
    {
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
        }

        auto source = LocalValue(21);
        LocalValue target = __rvalue(source);

        writeln(
            "isNested=", __traits(isNested, LocalValue),
            " source.value=", source.value,
            " target.value=", target.value);
    }
}
else version (PlacementMoveProbe)
{
    void main()
    {
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
        }

        align(LocalValue.alignof) ubyte[LocalValue.sizeof] storage = void;
        auto target = cast(LocalValue*) storage.ptr;

        auto source = LocalValue(22);
        auto placed = new (*target) LocalValue(__rvalue(source));

        writeln(
            "isNested=", __traits(isNested, LocalValue),
            " source.value=", source.value,
            " target.value=", placed.value,
            " same-address=", placed is target);

        destroy!false(*placed);
    }
}
else
{
    static assert(0, "select one probe mode");
}
