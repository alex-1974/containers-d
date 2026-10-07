module app;

import containers.work_stealing_deque : WorkStealingDeque;

struct PostblitValue
{
    ulong value;

    this(this) @safe @nogc nothrow
    {
    }
}

void main()
{
    WorkStealingDeque!(PostblitValue, 8) queue;
}
