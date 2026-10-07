module app;

import containers.research.work_stealing_deque : ResearchWorkStealingDeque;

alias Queue = ResearchWorkStealingDeque!(ulong, 8);

void consume(Queue queue)
{
}

void main()
{
    Queue queue;
    consume(queue);
}
