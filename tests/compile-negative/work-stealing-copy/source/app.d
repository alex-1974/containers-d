module app;

import containers.research.work_stealing_deque : ResearchWorkStealingDeque;

void main()
{
    ResearchWorkStealingDeque!(ulong, 8) original;
    auto copy = original;
}
