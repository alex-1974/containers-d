module app;

import containers.scratch_buffer : ScratchBuffer;

ref int escapeScratchRef() @safe
{
    auto scratch = ScratchBuffer!int(4);
    assert(scratch.tryPushBack(1));

    // Must fail under DIP1000: the reference borrows local owned storage.
    return scratch[0];
}

void main()
{
    ref value = escapeScratchRef();
    assert(value == 1);
}
