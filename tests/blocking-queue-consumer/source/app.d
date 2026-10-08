module app;

import containers :
    BlockingQueue,
    BlockingQueuePopStatus,
    BlockingQueuePushResult;
import core.thread : Thread;

void main()
{
    auto queue = new BlockingQueue!int(2);

    assert(queue.capacity == 2);
    assert(queue.tryPush(10) == BlockingQueuePushResult.pushed);
    assert(queue.tryPush(20) == BlockingQueuePushResult.pushed);
    assert(queue.tryPush(30) == BlockingQueuePushResult.full);

    assert(queue.close);
    assert(!queue.close);
    assert(queue.tryPush(40) == BlockingQueuePushResult.closed);

    auto first = queue.waitPop();
    auto second = queue.waitPop();
    auto done = queue.waitPop();

    assert(first.found && first.value == 10);
    assert(second.found && second.value == 20);
    assert(done.status == BlockingQueuePopStatus.closed);

    auto wakeQueue = new BlockingQueue!int(1);
    int received = -1;

    auto consumer = new Thread({
        auto result = wakeQueue.waitPop();
        assert(result.found);
        received = result.value;
    });

    consumer.start();
    Thread.yield();

    assert(wakeQueue.tryPush(77) == BlockingQueuePushResult.pushed);
    consumer.join();

    assert(received == 77);
    assert(wakeQueue.close);
}
