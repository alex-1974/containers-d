module app;

import containers.research.work_stealing_deque : ResearchWorkStealingDeque;

struct PostblitValue
{
    ulong value;

    this(this) @safe @nogc nothrow
    {
    }
}

void main()
{
    ResearchWorkStealingDeque!(PostblitValue, 8) queue;
}
