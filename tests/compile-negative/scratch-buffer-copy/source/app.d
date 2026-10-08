module app;

import containers.scratch_buffer : ScratchBuffer;

void main()
{
    auto source = ScratchBuffer!int(4);

    // Must fail: backing storage is uniquely owned.
    auto copied = source;
}
