module app;

import containers.work_stealing_deque : WorkStealingDeque;

struct OwningValue
{
    ulong value;

    ~this() @safe @nogc nothrow
    {
    }
}

void main()
{
    WorkStealingDeque!(OwningValue, 8) queue;
}
