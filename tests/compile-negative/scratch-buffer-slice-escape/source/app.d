module app;

import containers.scratch_buffer : ScratchBuffer;

int[] escapeScratchSlice() @safe
{
    auto scratch = ScratchBuffer!int(4);
    assert(scratch.tryPushBack(1));

    // Must fail under DIP1000: the slice borrows local owned storage.
    return scratch[];
}

void main()
{
    auto escaped = escapeScratchSlice();
    assert(escaped.length == 1);
}
