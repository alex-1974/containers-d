module app;

import containers.work_stealing_deque : WorkStealingDeque;

alias Queue = WorkStealingDeque!(ulong, 8);

void consume(Queue queue)
{
}

void main()
{
    Queue queue;
    consume(queue);
}
