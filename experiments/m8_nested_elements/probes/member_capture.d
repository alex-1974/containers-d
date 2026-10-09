module m8_member_capture_probe;

import std.stdio : stdout, writeln;

struct Host
{
    int context;

    version (TraitsProbe)
    void run()
    {
        Host* owner = &this;

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
                return owner.context;
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

    version (OrdinaryMoveProbe)
    void run()
    {
        Host* owner = &this;

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
                return owner.context;
            }
        }

        auto source = LocalValue(41);
        LocalValue target = __rvalue(source);

        writeln(
            "isNested=", __traits(isNested, LocalValue),
            " source.value=", source.value,
            " target.value=", target.value,
            " target.context=", target.contextValue);
    }

    version (PlacementMoveProbe)
    void run()
    {
        Host* owner = &this;

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
                return owner.context;
            }
        }

        align(LocalValue.alignof) ubyte[LocalValue.sizeof] storage = void;
        auto target = cast(LocalValue*) storage.ptr;

        auto source = LocalValue(42);
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

void main()
{
    Host host;
    host.context = 201;
    host.run();
}
