module m8_nested_minimal_probe;

import core.stdc.stdio : fflush, printf, stdout;

private void marker(const(char)* text)
{
    printf("%s\n", text);
    fflush(stdout);
}

version (TraitsProbe)
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

        printf(
            "isNested=%s constructCompiles=%s initCompiles=%s sizeof=%zu alignof=%zu\n",
            __traits(isNested, LocalValue) ? "true" : "false",
            __traits(compiles, LocalValue(1)) ? "true" : "false",
            __traits(compiles, LocalValue.init) ? "true" : "false",
            LocalValue.sizeof,
            LocalValue.alignof);
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

        auto source = LocalValue(11);
        marker("before-ordinary-move");
        LocalValue target = __rvalue(source);
        marker("after-ordinary-move");

        printf("source=%d target=%d\n", source.value, target.value);
    }
}
else version (PlacementConstructProbe)
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
        auto source = LocalValue(21);

        marker("before-placement-new");
        auto placed = new (*target) LocalValue(__rvalue(source));
        marker("after-placement-new");

        printf(
            "source=%d target=%d sameAddress=%s\n",
            source.value,
            placed.value,
            placed is target ? "true" : "false");
        fflush(stdout);
    }
}
else version (PlacementDestroyProbe)
{
    import core.lifetime : destroy;

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
        auto source = LocalValue(31);

        marker("before-placement-new");
        auto placed = new (*target) LocalValue(__rvalue(source));
        marker("after-placement-new");

        printf(
            "source=%d target=%d sameAddress=%s\n",
            source.value,
            placed.value,
            placed is target ? "true" : "false");
        fflush(stdout);

        marker("before-destroy");
        destroy!false(*placed);
        marker("after-destroy");
    }
}
else
{
    static assert(0, "select one M8 minimal probe mode");
}
