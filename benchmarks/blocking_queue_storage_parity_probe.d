module containers.blocking_queue_storage_parity_probe;

import containers.research.blocking_queue :
    BlockingQueuePopResult,
    BlockingQueuePopStatus,
    BlockingQueuePushResult,
    ResearchBlockingQueue;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t capacity = 64;

private final class ManualBlockingQueue
{
    private Mutex _mutex;
    private Condition _notEmpty;
    private int[] _storage;
    private size_t _head;
    private size_t _length;
    private bool _closed;

    this(size_t capacity)
    {
        _mutex = new Mutex;
        _notEmpty = new Condition(_mutex);
        _storage = new int[](capacity);
    }

    BlockingQueuePushResult tryPush(int value)
    {
        synchronized (_mutex)
        {
            if (_closed)
                return BlockingQueuePushResult.closed;

            if (_length == _storage.length)
                return BlockingQueuePushResult.full;

            const physical =
                (_head + _length) % _storage.length;

            _storage[physical] = value;
            ++_length;

            _notEmpty.notify();
            return BlockingQueuePushResult.pushed;
        }
    }

    BlockingQueuePopResult!int waitPop()
    {
        synchronized (_mutex)
        {
            while (_length == 0 && !_closed)
                _notEmpty.wait();

            if (_length == 0)
                return BlockingQueuePopResult!int(
                    BlockingQueuePopStatus.closed,
                    int.init);

            const value = _storage[_head];

            ++_head;
            if (_head == _storage.length)
                _head = 0;

            --_length;

            if (_length == 0)
                _head = 0;

            return BlockingQueuePopResult!int(
                BlockingQueuePopStatus.value,
                value);
        }
    }
}

private ulong mix(ulong state, int value) @safe @nogc nothrow
{
    return
        (state ^ cast(uint)value) *
        0x100000001B3UL;
}

pragma(inline, false)
extern(C) ulong bench_candidate(
    ResearchBlockingQueue!int queue,
    scope const(int)[] input,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (round; 0 .. rounds)
    {
        foreach (i, seed; input)
        {
            const value =
                seed ^ cast(int)(round + i);

            assert(
                queue.tryPush(value) ==
                BlockingQueuePushResult.pushed);
        }

        foreach (_; 0 .. input.length)
        {
            auto result = queue.waitPop();

            assert(
                result.status ==
                BlockingQueuePopStatus.value);

            checksum = mix(checksum, result.value);
        }
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_manual(
    ManualBlockingQueue queue,
    scope const(int)[] input,
    size_t rounds)
{
    ulong checksum = 0xCBF29CE484222325UL;

    foreach (round; 0 .. rounds)
    {
        foreach (i, seed; input)
        {
            const value =
                seed ^ cast(int)(round + i);

            assert(
                queue.tryPush(value) ==
                BlockingQueuePushResult.pushed);
        }

        foreach (_; 0 .. input.length)
        {
            auto result = queue.waitPop();

            assert(
                result.status ==
                BlockingQueuePopStatus.value);

            checksum = mix(checksum, result.value);
        }
    }

    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: blocking-queue-storage-parity <candidate|manual> <rounds>");
        return;
    }

    const rounds = to!size_t(args[2]);

    int[capacity] input;
    uint state =
        cast(uint)rounds ^
        0x6C8E_9CF5u;

    foreach (ref value; input)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        value = cast(int)state;
    }

    final switch (args[1])
    {
        case "candidate":
        {
            auto queue =
                new ResearchBlockingQueue!int(capacity);

            writeln("candidate ",
                bench_candidate(queue, input[], rounds));
            break;
        }

        case "manual":
        {
            auto queue =
                new ManualBlockingQueue(capacity);

            writeln("manual ",
                bench_manual(queue, input[], rounds));
            break;
        }
    }
}
