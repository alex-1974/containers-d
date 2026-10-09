module app;

import containers.runtime_ring_buffer : RingBuffer;
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
    auto value = RingBuffer!Nested(2);
}
