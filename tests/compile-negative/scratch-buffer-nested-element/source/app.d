module app;

import containers.scratch_buffer : ScratchBuffer;
import std.traits : isNested;

void main()
{
    int outer;

    struct Nested
    {
        int value;

        int contextValue() const
        {
            return outer;
        }
    }

    static assert(isNested!Nested);

    // Must fail: raw-storage families do not own or reconstruct T's hidden
    // lexical context.
    auto value = ScratchBuffer!Nested(2);
}
