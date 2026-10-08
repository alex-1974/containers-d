module app;

import containers : RingBuffer, ScratchBuffer, StaticRingBuffer, StaticVector, WorkStealingDeque, WorkStealingTakeResult;

struct SafeMovable
{
    int value;

    this(ref return scope SafeMovable rhs) @safe @nogc nothrow
    {
        value = rhs.value;
    }

    this(return scope SafeMovable rhs) @safe @nogc nothrow
    {
        value = rhs.value;
        rhs.value = -1;
    }
}

private void exerciseSafeCore() @safe @nogc nothrow
{
    WorkStealingDeque!(ulong, 8) work;
    static assert(work.capacity == 8);

    assert(work.tryPush(11));
    assert(work.tryPush(22));

    WorkStealingTakeResult!ulong stolen = work.steal();
    assert(stolen.found);
    assert(stolen.value == 11);

    auto owner = work.pop();
    assert(owner.found);
    assert(owner.value == 22);

    ulong[2] batchOutput;
    assert(work.stealBatch(batchOutput[]) == 0);

    ScratchBuffer!ubyte bytes;
    assert(bytes.tryReserve(4096));

    ubyte[4096] reference;
    foreach (round; 0 .. 128)
    {
        bytes.reset();

        const live = 2048 + ((round * 37 + 11) & 1023);
        foreach (i; 0 .. live)
        {
            const value =
                cast(ubyte)((round * 29 + i * 17) ^ (i >> 3));

            reference[i] = value;
            assert(bytes.tryPushBack(value));
        }

        assert(bytes.length == live);
        assert(bytes[] == reference[0 .. live]);
    }

    ScratchBuffer!int scratch;
    assert(scratch.tryReserve(8));
    assert(scratch.capacity == 8);
    assert(scratch.tryPushBack(5));
    assert(scratch.tryPushBack(6));
    assert(scratch[] == [5, 6]);
    assert(!scratch.tryReserve(16));
    scratch.reset();
    assert(scratch.tryReserve(16));
    assert(scratch.capacity == 16);
    assert(scratch.empty);

    StaticVector!(int, 4) vector;
    vector.pushBack(1);
    vector.pushBack(2);
    assert(vector.length == 2);
    assert(vector[] == [1, 2]);
    vector[1] = 3;
    assert(vector.back == 3);
    vector.popBack();
    assert(vector.length == 1);
    vector.clear();
    assert(vector.empty);

    StaticRingBuffer!(int, 3) buffer;

    assert(buffer.empty);
    assert(buffer.tryPushBack(10));
    assert(buffer.tryPushBack(20));
    assert(buffer.length == 2);
    assert(buffer.front == 10);
    assert(buffer.back == 20);
    assert(buffer[1] == 20);

    auto first = buffer.firstSegment;
    auto second = buffer.secondSegment;
    assert(first.length + second.length == buffer.length);
    assert(first[0] == 10);
    assert(first[1] == 20);
    assert(second.length == 0);

    first[1] = 21;
    assert(buffer.back == 21);

    buffer.popFront();
    assert(buffer.front == 21);

    buffer.clear();
    assert(buffer.empty);

    auto runtime = RingBuffer!int(4);
    assert(runtime.capacity == 4);
    assert(runtime.tryPushBack(100));
    assert(runtime.tryPushBack(200));
    assert(runtime.tryPushBack(300));

    runtime.popFront();
    assert(runtime.tryPushBack(400));
    assert(runtime.tryPushBack(500));

    auto runtimeFirst = runtime.firstSegment;
    auto runtimeSecond = runtime.secondSegment;
    assert(runtimeFirst.length + runtimeSecond.length == runtime.length);
    assert(runtime[0] == 200);
    assert(runtime.back == 500);

    runtime.clear();
    assert(runtime.empty);
    assert(runtime.capacity == 4);
}

void main() @nogc nothrow
{
    exerciseSafeCore();

    SafeMovable seed;
    seed.value = 77;

    StaticRingBuffer!(SafeMovable, 2) movable;
    assert(movable.tryPushBack(seed));

    auto moved = __rvalue(movable);
    assert(moved.length == 1);
    assert(moved.front.value == 77);

    auto runtime = RingBuffer!int(4);
    assert(runtime.tryPushBack(100));
    assert(runtime.tryPushBack(200));

    auto runtimeMoved = __rvalue(runtime);
    assert(runtime.capacity == 0);
    assert(runtimeMoved.capacity == 4);
    assert(runtimeMoved.length == 2);
    runtimeMoved.clear();
}
