/**
 * Bounded synchronized blocking FIFO queue.
 */
module containers.blocking_queue;

import containers.runtime_ring_buffer : RingBuffer;
import core.lifetime : emplace, forward;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import std.traits : Unqual, isCopyable;

/// Non-blocking producer outcome.
enum BlockingQueuePushResult
{
    /// The value was inserted.
    pushed,

    /// The open queue currently has no spare capacity.
    full,

    /// The queue is closed and rejects all future pushes.
    closed,
}

/// Blocking consumer outcome.
enum BlockingQueuePopStatus
{
    /// A queued value was returned.
    value,

    /// The queue is closed and fully drained.
    closed,
}

/// Result of a blocking pop operation.
struct BlockingQueuePopResult(T)
{
    BlockingQueuePopStatus status;
    T value;

    /// Whether this result contains a queued value.
    @property bool found() const @safe @nogc nothrow
    {
        return status == BlockingQueuePopStatus.value;
    }
}

/**
 * Bounded synchronized MPMC FIFO queue.
 *
 * The queue owns fixed runtime-capacity FIFO storage and synchronizes all
 * producer/consumer state through one mutex and condition variable.
 *
 * Producer admission is non-blocking: tryPush returns full instead of waiting
 * for capacity. Consumer removal is blocking: waitPop sleeps only while the
 * queue is empty and open.
 *
 * close is idempotent. After close, new pushes are rejected, values already in
 * the queue remain drainable, and all blocked consumers are woken. waitPop
 * returns closed only after the closed queue is empty.
 *
 * The initial production contract requires copyable T. Move-only synchronized
 * transfer remains a separate lifetime-contract problem.
 *
 * Construction may allocate the FIFO backing storage and synchronization
 * objects. Queue operations never resize or reacquire the FIFO backing storage.
 */
final class BlockingQueue(T)
if (isCopyable!T)
{
private:
    Mutex _mutex;
    Condition _notEmpty;
    RingBuffer!T _buffer = void;
    bool _closed;

    version (unittest)
    {
        size_t _testWaitingConsumers;
        size_t _testWakeReturns;
    }

public:
    /// Constructs a queue with fixed runtime capacity.
    this(size_t capacity)
    {
        _mutex = new Mutex;
        _notEmpty = new Condition(_mutex);
        emplace(&_buffer, capacity);
    }

    /// Fixed queue capacity selected at construction.
    @property size_t capacity()
    {
        synchronized (_mutex)
            return _buffer.capacity;
    }

    /**
     * Attempts one producer insertion without waiting for capacity.
     *
     * Returns pushed on success, full when the open queue has no spare slot,
     * and closed after producer admission has been closed.
     */
    BlockingQueuePushResult tryPush(U)(auto ref U value)
    if (is(Unqual!U == T) &&
        __traits(compiles, _buffer.tryPushBack(forward!value)))
    {
        synchronized (_mutex)
        {
            if (_closed)
                return BlockingQueuePushResult.closed;

            if (_buffer.full)
                return BlockingQueuePushResult.full;

            const accepted = _buffer.tryPushBack(forward!value);
            assert(accepted);

            _notEmpty.notify();
            return BlockingQueuePushResult.pushed;
        }
    }

    /**
     * Blocks until a value is available or the closed queue is fully drained.
     *
     * Spurious condition-variable wakes are harmless because the wait predicate
     * is always re-checked in a loop.
     */
    BlockingQueuePopResult!T waitPop()
    {
        synchronized (_mutex)
        {
            while (_buffer.empty && !_closed)
            {
                version (unittest)
                {
                    ++_testWaitingConsumers;
                    scope(exit) --_testWaitingConsumers;
                }

                _notEmpty.wait();

                version (unittest)
                    ++_testWakeReturns;
            }

            if (_buffer.empty)
            {
                return BlockingQueuePopResult!T(
                    BlockingQueuePopStatus.closed,
                    T.init);
            }

            T value = _buffer.front;
            _buffer.popFront();

            return BlockingQueuePopResult!T(
                BlockingQueuePopStatus.value,
                value);
        }
    }

    /**
     * Closes producer admission and wakes all blocked consumers.
     *
     * Returns true exactly for the first open -> closed transition.
     */
    bool close()
    {
        synchronized (_mutex)
        {
            if (_closed)
                return false;

            _closed = true;
            _notEmpty.notifyAll();
            return true;
        }
    }

    version (unittest)
    {
        private size_t testWaitingConsumers()
        {
            synchronized (_mutex)
                return _testWaitingConsumers;
        }

        private size_t testWakeReturns()
        {
            synchronized (_mutex)
                return _testWakeReturns;
        }

        private void testNotifyAll()
        {
            synchronized (_mutex)
                _notEmpty.notifyAll();
        }
    }
}

version (unittest)
{
    import core.atomic : atomicLoad, atomicOp, atomicStore;
    import core.thread : Thread;

    private void spinUntil(scope bool delegate() predicate)
    {
        foreach (_; 0 .. 1_000_000)
        {
            if (predicate())
                return;

            Thread.yield();
        }

        assert(false, "timed out waiting for deterministic queue state");
    }

    unittest
    {
        auto queue = new BlockingQueue!int(2);

        assert(queue.capacity == 2);
        assert(queue.tryPush(1) == BlockingQueuePushResult.pushed);
        assert(queue.tryPush(2) == BlockingQueuePushResult.pushed);
        assert(queue.tryPush(3) == BlockingQueuePushResult.full);

        assert(queue.close);
        assert(!queue.close);
        assert(queue.tryPush(4) == BlockingQueuePushResult.closed);

        auto first = queue.waitPop();
        auto second = queue.waitPop();
        auto done = queue.waitPop();

        assert(first.found && first.value == 1);
        assert(second.found && second.value == 2);
        assert(done.status == BlockingQueuePopStatus.closed);
    }

    unittest
    {
        auto queue = new BlockingQueue!int(2);

        shared bool done;
        int received = -1;

        auto consumer = new Thread({
            auto result = queue.waitPop();
            assert(result.status == BlockingQueuePopStatus.value);
            received = result.value;
            atomicStore(done, true);
        });

        consumer.start();
        spinUntil(() => queue.testWaitingConsumers == 1);

        assert(queue.tryPush(42) == BlockingQueuePushResult.pushed);

        consumer.join();
        assert(atomicLoad(done));
        assert(received == 42);
    }

    unittest
    {
        auto queue = new BlockingQueue!int(4);

        enum size_t count = 4;
        Thread[count] consumers;
        shared size_t closedCount;

        foreach (i; 0 .. count)
        {
            consumers[i] = new Thread({
                auto result = queue.waitPop();

                if (result.status == BlockingQueuePopStatus.closed)
                    atomicOp!"+="(closedCount, cast(size_t)1);
            });

            consumers[i].start();
        }

        spinUntil(() => queue.testWaitingConsumers == count);

        assert(queue.close);
        assert(!queue.close);

        foreach (consumer; consumers)
            consumer.join();

        assert(atomicLoad(closedCount) == count);
        assert(queue.tryPush(1) == BlockingQueuePushResult.closed);
    }

    unittest
    {
        auto queue = new BlockingQueue!int(1);

        shared bool done;
        int received = -1;

        auto consumer = new Thread({
            auto result = queue.waitPop();
            assert(result.status == BlockingQueuePopStatus.value);
            received = result.value;
            atomicStore(done, true);
        });

        consumer.start();
        spinUntil(() => queue.testWaitingConsumers == 1);

        const before = queue.testWakeReturns;
        queue.testNotifyAll();

        spinUntil(() =>
            queue.testWakeReturns > before &&
            queue.testWaitingConsumers == 1);

        assert(!atomicLoad(done));

        assert(queue.tryPush(7) == BlockingQueuePushResult.pushed);
        consumer.join();

        assert(atomicLoad(done));
        assert(received == 7);
    }

    unittest
    {
        enum int perProducer = 2_000;
        enum int producerCount = 2;
        enum int consumerCount = 2;
        enum int total = perProducer * producerCount;

        auto queue = new BlockingQueue!int(64);

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
    }
}
