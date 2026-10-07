module app;

import containers : WorkStealingDeque;
import containers.work_stealing_deque : WorkStealingTakeResult;

private shared ulong persistentValue;

private struct Handle
{
    shared(ulong)* ptr;
}

private void exerciseRootImport()
    @safe @nogc nothrow
{
    WorkStealingDeque!(ulong, 8) queue;

    static assert(queue.capacity == 8);

    assert(queue.tryPush(10));
    assert(queue.tryPush(20));
    assert(queue.tryPush(30));

    WorkStealingTakeResult!ulong owner = queue.pop();
    assert(owner.found);
    assert(owner.value == 30);

    auto thief = queue.steal();
    assert(thief.found);
    assert(thief.value == 10);

    ulong[4] batch = void;
    const taken = queue.stealBatch(batch[]);

    assert(taken == 1);
    assert(batch[0] == 20);
}

private void exerciseSharedHandle()
    @safe @nogc nothrow
{
    WorkStealingDeque!(Handle, 4) queue;

    auto handle = Handle(&persistentValue);

    assert(queue.tryPush(handle));

    auto result = queue.steal();
    assert(result.found);
    assert(result.value.ptr is &persistentValue);
}

void main()
{
    exerciseRootImport();
    exerciseSharedHandle();
}
