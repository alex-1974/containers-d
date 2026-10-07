module app;

import containers.research.work_stealing_deque : ResearchWorkStealingDeque;

void main()
{
    ResearchWorkStealingDeque!(ulong, 8) source;
    auto moved = __rvalue(source);
}
