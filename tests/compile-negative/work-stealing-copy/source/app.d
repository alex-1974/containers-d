module app;

import containers.work_stealing_deque : WorkStealingDeque;

void main()
{
    WorkStealingDeque!(ulong, 8) original;
    auto copy = original;
}
