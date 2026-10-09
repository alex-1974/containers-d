module containers.m8_nested_integration_probe;

import containers : StaticRingBuffer, StaticVector;
import containers.internal.element_lifetime : PlacementMoveOps;
import containers.internal.inline_storage : InlineRawStorage;

import core.lifetime : emplace;
import std.stdio : writeln;
import std.traits : hasIndirections;

version (PublicContractProbe)
{
    void main()
    {
        int context = 101;

        struct Nested
        {
            int value;

            this(int value)
            {
                this.value = value;
            }

            int contextValue() const
            {
                return context;
            }
        }

        enum bool ringCompiles = __traits(compiles, {
            StaticRingBuffer!(Nested, 2) ring;
        });
        enum bool vectorCompiles = __traits(compiles, {
            StaticVector!(Nested, 2) vector;
        });

        writeln(
            "isNested=", __traits(isNested, Nested),
            " hasIndirections=", hasIndirections!Nested,
            " ringCompiles=", ringCompiles,
            " vectorCompiles=", vectorCompiles);

        assert(__traits(isNested, Nested));
        assert(hasIndirections!Nested);
        assert(!ringCompiles);
        assert(!vectorCompiles);
    }
}
else version (InternalStorageProbe)
{
    void main()
    {
        int context = 102;

        struct Nested
        {
            int value;

            this(int value)
            {
                this.value = value;
            }

            int contextValue() const
            {
                return context;
            }
        }

        alias Storage = InlineRawStorage!(Nested, 2);
        Storage storage;

        auto first = storage.slotPointer(0);
        auto second = storage.slotPointer(1);

        writeln(
            "isNested=", __traits(isNested, Nested),
            " hasIndirections=", hasIndirections!Nested,
            " storageHasIndirections=", hasIndirections!Storage,
            " firstAligned=",
                cast(size_t) first % Nested.alignof == 0,
            " secondAligned=",
                cast(size_t) second % Nested.alignof == 0);

        assert(first !is null);
        assert(second !is null);
        assert(cast(size_t) first % Nested.alignof == 0);
        assert(cast(size_t) second % Nested.alignof == 0);
    }
}
else version (InternalDirectPlacementProbe)
{
    void main()
    {
        int context = 105;

        struct Nested
        {
            int value;

            this(int value)
            {
                this.value = value;
            }

            int contextValue() const
            {
                return context;
            }
        }

        alias Storage = InlineRawStorage!(Nested, 1);
        Storage storage;

        writeln("before-internal-direct-placement");
        auto placed = new (*storage.slotPointer(0)) Nested(41);
        writeln("after-internal-direct-placement");

        writeln(
            "value=", placed.value,
            " context=", placed.contextValue);

        destroy!false(*placed);
    }
}
else version (InternalEmplaceProbe)
{
    void main()
    {
        int context = 103;

        struct Nested
        {
            int value;

            this(int value)
            {
                this.value = value;
            }

            int contextValue() const
            {
                return context;
            }
        }

        alias Storage = InlineRawStorage!(Nested, 1);
        Storage storage;

        writeln("before-internal-emplace");
        auto placed = emplace(storage.slotPointer(0), 51);
        writeln("after-internal-emplace");

        writeln(
            "value=", placed.value,
            " context=", placed.contextValue);

        destroy!false(*placed);
    }
}
else version (InternalPlacementMoveProbe)
{
    void main()
    {
        int context = 104;

        struct Nested
        {
            int value;

            this(int value)
            {
                this.value = value;
            }

            this(return scope Nested rhs)
            {
                value = rhs.value;
                rhs.value = -1;
            }

            int contextValue() const
            {
                return context;
            }
        }

        struct Ops
        {
            mixin PlacementMoveOps!Nested;
        }

        alias Storage = InlineRawStorage!(Nested, 1);
        Storage storage;
        auto source = Nested(61);

        writeln("before-internal-placement-move");
        auto placed = Ops.placementMoveConstruct(
            storage.slotPointer(0), source);
        writeln("after-internal-placement-move");

        writeln(
            "source=", source.value,
            " value=", placed.value,
            " context=", placed.contextValue);

        destroy!false(*placed);
    }
}
else version (StaticControlProbe)
{
    void main()
    {
        static struct Value
        {
            int value;

            this(int value)
            {
                this.value = value;
            }
        }

        static assert(!__traits(isNested, Value));

        alias Storage = InlineRawStorage!(Value, 1);
        Storage storage;

        writeln("before-static-control-emplace");
        auto placed = emplace(storage.slotPointer(0), 71);
        writeln("after-static-control-emplace");

        writeln("value=", placed.value);
        assert(placed.value == 71);

        destroy!false(*placed);
    }
}
else
{
    static assert(0, "select one M8 integration probe mode");
}
