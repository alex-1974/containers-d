module app;

import containers.research.blocking_queue :
    BlockingQueuePopStatus,
    BlockingQueuePushResult,
    ResearchBlockingQueue;
import core.atomic : atomicLoad, atomicStore;
import core.thread : Thread;

private void spinUntil(scope bool delegate() predicate)
{
    foreach (_; 0 .. 1_000_000)
    {
        if (predicate())
            return;

        Thread.yield();
    }

    assert(false, "timed out waiting for deterministic test state");
}

private void testPushWake()
{
    auto queue = new ResearchBlockingQueue!int(2);

    shared bool done;
    int received = -1;

    auto consumer = new Thread({
        auto result = queue.waitPop();
        assert(result.status == BlockingQueuePopStatus.value);
        received = result.value;
        atomicStore(done, true);
    });

    consumer.start();

    spinUntil(() => queue.researchWaitingConsumers == 1);

    assert(queue.tryPush(42) == BlockingQueuePushResult.pushed);

    consumer.join();

    assert(atomicLoad(done));
    assert(received == 42);
}

private void testCloseWakeAll()
{
    auto queue = new ResearchBlockingQueue!int(4);

    enum size_t count = 4;
    Thread[count] consumers;
    bool[count] closedResults;

    Thread makeConsumer(size_t index)
    {
        return new Thread({
            auto result = queue.waitPop();
            closedResults[index] =
                result.status == BlockingQueuePopStatus.closed;
        });
    }

    foreach (i; 0 .. count)
    {
        consumers[i] = makeConsumer(i);
        consumers[i].start();
    }

    spinUntil(() => queue.researchWaitingConsumers == count);

    assert(queue.close);
    assert(!queue.close);

    foreach (consumer; consumers)
        consumer.join();

    foreach (closed; closedResults)
        assert(closed);

    assert(queue.tryPush(1) == BlockingQueuePushResult.closed);
}

private void testSyntheticWakeRechecksPredicate()
{
    auto queue = new ResearchBlockingQueue!int(1);

    shared bool done;
    int received = -1;

    auto consumer = new Thread({
        auto result = queue.waitPop();
        assert(result.status == BlockingQueuePopStatus.value);
        received = result.value;
        atomicStore(done, true);
    });

    consumer.start();

    spinUntil(() => queue.researchWaitingConsumers == 1);

    const before = queue.researchWakeReturns;
    queue.researchNotifyAll();

    spinUntil(() =>
        queue.researchWakeReturns > before &&
        queue.researchWaitingConsumers == 1);

    // The synthetic notification changed no queue predicate.
    assert(!atomicLoad(done));

    assert(queue.tryPush(7) == BlockingQueuePushResult.pushed);
    consumer.join();

    assert(atomicLoad(done));
    assert(received == 7);
}

private void testCloseAndDrain()
{
    auto queue = new ResearchBlockingQueue!int(3);

    assert(queue.tryPush(10) == BlockingQueuePushResult.pushed);
    assert(queue.tryPush(20) == BlockingQueuePushResult.pushed);
    assert(queue.close);

    auto first = queue.waitPop();
    auto second = queue.waitPop();
    auto done = queue.waitPop();

    assert(first.status == BlockingQueuePopStatus.value);
    assert(second.status == BlockingQueuePopStatus.value);
    assert(done.status == BlockingQueuePopStatus.closed);

    assert(first.value == 10);
    assert(second.value == 20);
}

private void testWorkerReferencesKeepQueueAlive()
{
    alias Queue = ResearchBlockingQueue!int;

    Queue queue = new Queue(2);

    shared bool producerDone;
    shared bool consumerDone;
    int received = -1;

    Thread makeConsumer(Queue owned)
    {
        return new Thread({
            auto value = owned.waitPop();
            assert(value.status == BlockingQueuePopStatus.value);
            received = value.value;

            auto done = owned.waitPop();
            assert(done.status == BlockingQueuePopStatus.closed);

            atomicStore(consumerDone, true);
        });
    }

    Thread makeProducer(Queue owned)
    {
        return new Thread({
            assert(
                owned.tryPush(91) ==
                BlockingQueuePushResult.pushed);
            assert(owned.close);
            atomicStore(producerDone, true);
        });
    }

    auto consumer = makeConsumer(queue);
    auto producer = makeProducer(queue);

    consumer.start();
    producer.start();

    // The caller drops its own class reference. Each worker owns an
    // independent captured reference for the duration of its operation.
    queue = null;

    producer.join();
    consumer.join();

    assert(atomicLoad(producerDone));
    assert(atomicLoad(consumerDone));
    assert(received == 91);
}

private void testMpmcExactAccounting()
{
    enum int perProducer = 2_000;
    enum int producerCount = 2;
    enum int consumerCount = 2;
    enum int total = perProducer * producerCount;

    auto queue = new ResearchBlockingQueue!int(64);

    Thread[producerCount] producers;
    Thread[consumerCount] consumers;

    int[][consumerCount] consumed;

    Thread makeProducer(size_t producerIndex)
    {
        return new Thread({
            const base = cast(int)producerIndex * perProducer;

            foreach (i; 0 .. perProducer)
            {
                const value = base + cast(int)i;

                for (;;)
                {
                    final switch (queue.tryPush(value))
                    {
                        case BlockingQueuePushResult.pushed:
                            break;

                        case BlockingQueuePushResult.full:
                            Thread.yield();
                            continue;

                        case BlockingQueuePushResult.closed:
                            assert(false, "producer observed unexpected close");
                    }

                    break;
                }
            }
        });
    }

    Thread makeConsumer(size_t consumerIndex)
    {
        return new Thread({
            for (;;)
            {
                auto result = queue.waitPop();

                if (result.status == BlockingQueuePopStatus.closed)
                    break;

                consumed[consumerIndex] ~= result.value;
            }
        });
    }

    foreach (producerIndex; 0 .. producerCount)
    {
        producers[producerIndex] = makeProducer(producerIndex);
        producers[producerIndex].start();
    }

    foreach (consumerIndex; 0 .. consumerCount)
    {
        consumers[consumerIndex] = makeConsumer(consumerIndex);
        consumers[consumerIndex].start();
    }

    foreach (producer; producers)
        producer.join();

    assert(queue.close);

    foreach (consumer; consumers)
        consumer.join();

    size_t[total] counts;

    size_t observed;
    foreach (values; consumed)
    {
        observed += values.length;

        foreach (value; values)
        {
            assert(value >= 0 && value < total);
            ++counts[value];
        }
    }

    assert(observed == total);

    foreach (count; counts)
        assert(count == 1);

    assert(queue.empty);
}

void main()
{
    testPushWake();
    testCloseWakeAll();
    testSyntheticWakeRechecksPredicate();
    testCloseAndDrain();
    testWorkerReferencesKeepQueueAlive();
    testMpmcExactAccounting();
}
