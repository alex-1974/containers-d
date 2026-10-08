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
    /// Whether this result carries a value or reports final closure.
    BlockingQueuePopStatus status;

    /// Removed value when status is `value`; otherwise `T.init`.
    T value;

    /// Whether this result contains a queued value.
    @property bool found() const @safe @nogc nothrow
    {
        return status == BlockingQueuePopStatus.value;
    }
}

/**
 * Bounded synchronized FIFO for handing work from producer threads to consumer
 * threads.
 *
 * Use BlockingQueue when the queue has a fixed maximum size, producers must
 * never wait for free capacity, and consumers should sleep while no work is
 * available. A producer learns immediately whether a value was accepted, the
 * queue is temporarily full, or the queue has been closed. A consumer waits
 * until it can receive a value or until a closed queue has been fully drained.
 *
 * The queue owns runtime-capacity FIFO storage and protects the complete queue
 * state with one mutex and one condition variable. The contract permits
 * multiple producers and multiple consumers. It is not a lock-free queue and
 * it does not provide scheduler, retry, timeout, cancellation, or overflow
 * policy.
 *
 * `close` is idempotent. Closing rejects future pushes, leaves values already
 * queued available in FIFO order, and wakes all blocked consumers. `waitPop`
 * reports `closed` only after the queue is both closed and empty.
 *
 * The first production contract requires copyable `T`. Move-only synchronized
 * transfer remains a separate lifetime-contract problem.
 *
 * Params:
 *   T = copyable element type transferred through the queue
 *
 * Allocation:
 *   Construction may allocate the RingBuffer backing storage, Mutex, Condition,
 *   and runtime synchronization resources. `tryPush`, `waitPop`, and `close`
 *   never resize or reacquire the FIFO backing storage.
 *
 * Thread_Safety:
 *   The public operations may be called concurrently by multiple producer and
 *   consumer threads. The queue object itself has synchronized identity and
 *   should be shared by reference.
 *
 * Notes:
 *   `length`, `empty`, `full`, and `closed` snapshots are deliberately not
 *   part of the public API because their values may become stale immediately
 *   after observation.
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
    /**
     * Constructs a queue with fixed runtime capacity.
     *
     * Params:
     *   capacity = maximum number of queued values; zero creates a queue that
     *              is always full until it is closed
     *
     * Allocation:
     *   May allocate backing storage and synchronization objects.
     */
    this(size_t capacity)
    {
        _mutex = new Mutex;
        _notEmpty = new Condition(_mutex);
        emplace(&_buffer, capacity);
    }

    /**
     * Returns the fixed queue capacity selected at construction.
     *
     * Returns:
     *   Maximum number of queued values. The value never changes during the
     *   queue lifetime, so callers may safely use it for configuration logic.
     */
    @property size_t capacity()
    {
        synchronized (_mutex)
            return _buffer.capacity;
    }

    /**
     * Attempts to append one value without waiting for free capacity.
     *
     * Params:
     *   value = value to copy into the queue when a slot is available
     *
     * Returns:
     *   `pushed` when the value was inserted, `full` when the open queue has no
     *   spare slot, or `closed` after producer admission has been closed.
     *
     * Failure:
     *   `full` and `closed` leave the queued sequence unchanged.
     *
     * Allocation:
     *   Does not resize or reacquire queue backing storage.
     *
     * Thread_Safety:
     *   May be called concurrently by multiple producers and consumers.
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
     * Waits for the next FIFO value or for final queue closure.
     *
     * Returns:
     *   A result with status `value` and the removed element when work is
     *   available. Returns status `closed` with `T.init` only after `close` has
     *   been called and every value queued before close has been drained.
     *
     * Blocking:
     *   Sleeps only while the queue is empty and still open. Spurious condition
     *   wakes are harmless because the state predicate is always re-checked in
     *   a loop.
     *
     * Allocation:
     *   Does not resize or reacquire queue backing storage.
     *
     * Thread_Safety:
     *   May be called concurrently by multiple consumers and producers.
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
     * Closes producer admission and wakes every blocked consumer.
     *
     * Values already queued remain available to `waitPop` in FIFO order.
     *
     * Returns:
     *   `true` exactly for the first open-to-closed transition; `false` when
     *   the queue was already closed.
     *
     * Thread_Safety:
     *   May run concurrently with producers and consumers. Once the transition
     *   succeeds, all later `tryPush` calls return `closed`.
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

/// A bounded work handoff queue keeps producer backpressure explicit.
unittest
{
    // A producer never blocks for space. The caller chooses what to do when
    // temporary backpressure reports full.
    auto jobs = new BlockingQueue!int(2);

    assert(jobs.tryPush(10) == BlockingQueuePushResult.pushed);
    assert(jobs.tryPush(20) == BlockingQueuePushResult.pushed);
    assert(jobs.tryPush(30) == BlockingQueuePushResult.full);

    // Closing stops new work but does not discard work already accepted.
    assert(jobs.close);
    assert(jobs.tryPush(40) == BlockingQueuePushResult.closed);

    auto first = jobs.waitPop();
    auto second = jobs.waitPop();
    auto done = jobs.waitPop();

    assert(first.found && first.value == 10);
    assert(second.found && second.value == 20);
    assert(done.status == BlockingQueuePopStatus.closed);
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
