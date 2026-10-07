/**
 * M7 research prototype for a bounded synchronized blocking FIFO.
 *
 * This module is intentionally not public API.
 */
module containers.research.blocking_queue;

import containers.runtime_ring_buffer : RingBuffer;
import core.lifetime : emplace, forward;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import std.traits : Unqual, isCopyable;

/// Non-blocking producer outcome.
enum BlockingQueuePushResult
{
    pushed,
    full,
    closed,
}

/// Blocking consumer outcome.
enum BlockingQueuePopStatus
{
    value,
    closed,
}

/// Result of waitPop.
struct BlockingQueuePopResult(T)
{
    BlockingQueuePopStatus status;
    T value;

    @property bool found() const @safe @nogc nothrow
    {
        return status == BlockingQueuePopStatus.value;
    }
}

/**
 * Research bounded MPMC blocking queue.
 *
 * RingBuffer owns bounded FIFO storage. Mutex/Condition own synchronization.
 *
 * The first research stage admits copyable T because waitPop must transfer a
 * stored value out of the queue before RingBuffer ends the source lifetime.
 * Move-only cross-thread transfer is a separate lifetime contract question.
 */
final class ResearchBlockingQueue(T)
if (isCopyable!T)
{
private:
    Mutex _mutex;
    Condition _notEmpty;
    RingBuffer!T _buffer = void;
    bool _closed;
    size_t _waitingConsumers;
    size_t _researchWakeReturns;

public:
    this(size_t capacity)
    {
        _mutex = new Mutex;
        _notEmpty = new Condition(_mutex);
        emplace(&_buffer, capacity);
    }

    @disable this(this);

    size_t capacity()
    {
        synchronized (_mutex)
            return _buffer.capacity;
    }

    size_t length()
    {
        synchronized (_mutex)
            return _buffer.length;
    }

    bool empty()
    {
        synchronized (_mutex)
            return _buffer.empty;
    }

    bool full()
    {
        synchronized (_mutex)
            return _buffer.full;
    }

    bool closed()
    {
        synchronized (_mutex)
            return _closed;
    }

    /**
     * Attempts one producer insertion without blocking for capacity.
     *
     * A successful push notifies one waiting consumer.
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
     * Close-and-drain semantics:
     * - values queued before close are still returned in FIFO order;
     * - closed is returned only when closed && empty.
     *
     * The predicate is re-checked in a loop after every condition wake so
     * spurious notifications do not change semantics.
     */
    BlockingQueuePopResult!T waitPop()
    {
        synchronized (_mutex)
        {
            while (_buffer.empty && !_closed)
            {
                ++_waitingConsumers;
                scope(exit) --_waitingConsumers;
                _notEmpty.wait();

                version (ContainersBlockingQueueResearchProbe)
                    ++_researchWakeReturns;
            }

            if (_buffer.empty)
                return BlockingQueuePopResult!T(
                    BlockingQueuePopStatus.closed,
                    T.init);

            T value = _buffer.front;
            _buffer.popFront();

            return BlockingQueuePopResult!T(
                BlockingQueuePopStatus.value,
                value);
        }
    }

    /**
     * Closes producer admission and wakes every waiting consumer.
     *
     * Returns true exactly for the state transition open -> closed.
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

    version (ContainersBlockingQueueResearchProbe)
    {
        /// Number of consumers currently inside Condition.wait.
        size_t researchWaitingConsumers()
        {
            synchronized (_mutex)
                return _waitingConsumers;
        }

        /// Number of returns from Condition.wait, including synthetic wakes.
        size_t researchWakeReturns()
        {
            synchronized (_mutex)
                return _researchWakeReturns;
        }

        /// Sends a notification without changing queue state.
        void researchNotifyAll()
        {
            synchronized (_mutex)
                _notEmpty.notifyAll();
        }
    }
}

unittest
{
    alias Queue = ResearchBlockingQueue!int;

    auto queue = new Queue(2);

    assert(queue.capacity == 2);
    assert(queue.empty);
    assert(!queue.closed);

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
