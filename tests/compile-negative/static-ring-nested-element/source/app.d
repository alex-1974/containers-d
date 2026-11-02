module app;

import containers.ring_buffer : StaticRingBuffer;
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
    StaticRingBuffer!(Nested, 2) value;
}
