module app;

import containers.scratch_buffer : ScratchBuffer;

void main()
{
    auto lhs = ScratchBuffer!int(4);
    auto rhs = ScratchBuffer!int(4);

    // Must fail: owning identity assignment is unavailable.
    lhs = rhs;
}
