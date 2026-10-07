module app;

import containers.research.work_stealing_deque : ResearchWorkStealingDeque;

struct OwningValue
{
    ulong value;

    ~this() @safe @nogc nothrow
    {
    }
}

void main()
{
    ResearchWorkStealingDeque!(OwningValue, 8) queue;
}
