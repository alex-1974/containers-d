/**
 * M3.3 whole-operation benchmark for runtime-capacity RingBuffer hot paths.
 *
 * This probe keeps the public RingBuffer as an actual-production baseline and
 * mirrors the relevant int-sized runtime implementation in ProbeRing so only
 * physical-index normalization can be varied. ProbeRing.tailRoom is the
 * calibration control; ProbeRing.addCarry is the DMD candidate from stage A.
 *
 * Setup, allocation, deterministic operation generation and output are outside
 * the Callgrind collection region.
 */
module containers.runtime_ring_buffer_operation_probe;

import containers.internal.runtime_storage : RuntimeStorageOwner;
import containers.runtime_ring_buffer : RingBuffer;
import core.lifetime : emplace, forward;
import std.conv : to;
import std.stdio : stderr, writeln;
import std.traits : hasElaborateDestructor, Unqual;

enum size_t operationCount = 256;

enum WrapStrategy
{
    tailRoom,
    addCarry,
}

struct Operation
{
    size_t value;
    size_t logicalIndex;
    bool inspectSegments;
}

/**
 * Benchmark-local mirror of the relevant RingBuffer implementation.
 *
 * Keep this deliberately close to production RingBuffer. The tailRoom
 * specialization exists only to calibrate that this mirror represents the
 * actual hot path closely enough for candidate comparison.
 */
private struct ProbeRing(T, WrapStrategy strategy)
{
    RuntimeStorageOwner!T _storage;
    size_t _head;
    size_t _length;

    ref T borrowedSlot(size_t physicalIndex) scope return @trusted
    {
        return *_storage.slotPointer(physicalIndex);
    }

    T[] borrowedSlice(
        size_t physicalStart,
        size_t count) scope return @trusted @nogc nothrow
    {
        return _storage.slotSlice(physicalStart, count);
    }

    size_t physicalIndex(size_t logicalIndex) const @safe @nogc nothrow
    {
        assert(logicalIndex < capacity);
        assert(capacity != 0);
        assert(_head < capacity);

        static if (strategy == WrapStrategy.tailRoom)
        {
            const tailRoom = capacity - _head;

            if (logicalIndex < tailRoom)
                return _head + logicalIndex;

            return logicalIndex - tailRoom;
        }
        else static if (strategy == WrapStrategy.addCarry)
        {
            size_t index = _head + logicalIndex;

            if (index < _head || index >= capacity)
                index -= capacity;

            return index;
        }
        else
        {
            static assert(false, "unsupported probe strategy");
        }
    }

    void endSlotLifetime(size_t physicalIndex)
    {
        static if (hasElaborateDestructor!T)
            destroy!false(*_storage.slotPointer(physicalIndex));

        _storage.clearVacatedSlot(physicalIndex);
    }

    void advanceHead() @safe @nogc nothrow
    {
        assert(capacity != 0);
        assert(_head < capacity);

        ++_head;
        if (_head == capacity)
            _head = 0;
    }

public:
    this(size_t capacity)
    {
        _storage.initialize(capacity);
    }

    @disable this(ref return scope typeof(this) rhs);
    @disable ref typeof(this) opAssign(ref typeof(this) rhs);

    ~this()
    {
        clear();
    }

    size_t capacity() const @safe @nogc nothrow
    {
        return _storage.capacity;
    }

    size_t length() const @safe @nogc nothrow
    {
        return _length;
    }

    bool empty() const @safe @nogc nothrow
    {
        return _length == 0;
    }

    bool full() const @safe @nogc nothrow
    {
        return _length == capacity;
    }

    ref T front() scope return
    {
        assert(!empty);
        return borrowedSlot(_head);
    }

    ref T opIndex(size_t logicalIndex) scope return
    {
        assert(logicalIndex < _length);
        return borrowedSlot(physicalIndex(logicalIndex));
    }

    T[] firstSegment() scope return @trusted @nogc nothrow
    {
        if (empty)
            return null;

        const physicalRemaining = capacity - _head;
        const count = _length < physicalRemaining
            ? _length
            : physicalRemaining;

        return borrowedSlice(_head, count);
    }

    T[] secondSegment() scope return @trusted @nogc nothrow
    {
        if (empty)
            return null;

        const firstCount = firstSegment.length;
        return borrowedSlice(0, _length - firstCount);
    }

    bool tryPushBack(U)(auto ref U value)
    if (is(Unqual!U == T) &&
        __traits(compiles, emplace(cast(T*) null, forward!value)))
    {
        if (full)
            return false;

        const physical = physicalIndex(_length);
        emplace(_storage.slotPointer(physical), forward!value);
        ++_length;
        return true;
    }

    void popFront()
    {
        assert(!empty);

        const physical = _head;
        endSlotLifetime(physical);

        --_length;

        if (_length == 0)
            _head = 0;
        else
            advanceHead();
    }

    void clear()
    {
        while (!empty)
            popFront();
    }
}

private void fillOperations(
    ref Operation[operationCount] operations,
    size_t capacity) nothrow @safe @nogc
{
    assert(capacity >= 3);

    uint state = 0xA11C_E551;

    foreach (i, ref operation; operations)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;

        operation.value =
            cast(size_t) state ^ (cast(size_t) i << 32);
        operation.logicalIndex = state % capacity;
        operation.inspectSegments = (state & 0x0F) == 0;
    }
}

private void prepareWrapped(Buffer)(ref Buffer buffer)
{
    const capacity = buffer.capacity;
    assert(capacity >= 3);

    foreach (i; 0 .. capacity)
        assert(buffer.tryPushBack(i + 1));

    const shift = capacity / 3;

    foreach (_; 0 .. shift)
        buffer.popFront();

    foreach (i; 0 .. shift)
        assert(buffer.tryPushBack(capacity + i + 1));

    assert(buffer.full);
    assert(buffer.length == capacity);
    assert(buffer.firstSegment.length + buffer.secondSegment.length == capacity);
    assert(buffer.secondSegment.length != 0);
}

private ulong runIndex(Buffer)(
    ref Buffer buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const operation; operations)
            checksum += buffer[operation.logicalIndex];
    }

    return checksum;
}

private ulong runPushPop(Buffer)(
    ref Buffer buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const operation; operations)
        {
            buffer.popFront();
            assert(buffer.tryPushBack(operation.value));
            checksum += buffer.front;
        }
    }

    return checksum;
}

private ulong runSegments(Buffer)(
    ref Buffer buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (_operation; operations)
        {
            auto first = buffer.firstSegment;
            auto second = buffer.secondSegment;

            checksum += first.length + second.length;

            if (first.length != 0)
                checksum += first[0];

            if (second.length != 0)
                checksum += second[0];
        }
    }

    return checksum;
}

private ulong runMixed(Buffer)(
    ref Buffer buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    ulong checksum;

    foreach (_; 0 .. rounds)
    {
        foreach (ref const operation; operations)
        {
            buffer.popFront();
            assert(buffer.tryPushBack(operation.value));

            checksum += buffer[operation.logicalIndex];

            if (operation.inspectSegments)
            {
                auto first = buffer.firstSegment;
                auto second = buffer.secondSegment;
                checksum += first.length + second.length;
            }
        }
    }

    return checksum;
}

alias Actual = RingBuffer!size_t;
alias TailRoomProbe = ProbeRing!(size_t, WrapStrategy.tailRoom);
alias AddCarryProbe = ProbeRing!(size_t, WrapStrategy.addCarry);

pragma(inline, false)
extern(C) ulong bench_actual_index(
    ref Actual buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runIndex(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_actual_pushpop(
    ref Actual buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runPushPop(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_actual_segments(
    ref Actual buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runSegments(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_actual_mixed(
    ref Actual buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runMixed(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_tailroom_index(
    ref TailRoomProbe buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runIndex(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_tailroom_pushpop(
    ref TailRoomProbe buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runPushPop(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_tailroom_segments(
    ref TailRoomProbe buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runSegments(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_tailroom_mixed(
    ref TailRoomProbe buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runMixed(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_addcarry_index(
    ref AddCarryProbe buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runIndex(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_addcarry_pushpop(
    ref AddCarryProbe buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runPushPop(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_addcarry_segments(
    ref AddCarryProbe buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runSegments(buffer, operations, rounds);
}

pragma(inline, false)
extern(C) ulong bench_addcarry_mixed(
    ref AddCarryProbe buffer,
    scope const Operation[] operations,
    size_t rounds)
{
    return runMixed(buffer, operations, rounds);
}

private ulong runActual(
    string workload,
    size_t capacity,
    scope const Operation[] operations,
    size_t rounds)
{
    auto buffer = Actual(capacity);
    prepareWrapped(buffer);

    final switch (workload)
    {
        case "index":
            return bench_actual_index(buffer, operations, rounds);
        case "pushpop":
            return bench_actual_pushpop(buffer, operations, rounds);
        case "segments":
            return bench_actual_segments(buffer, operations, rounds);
        case "mixed":
            return bench_actual_mixed(buffer, operations, rounds);
    }
}

private ulong runTailRoom(
    string workload,
    size_t capacity,
    scope const Operation[] operations,
    size_t rounds)
{
    auto buffer = TailRoomProbe(capacity);
    prepareWrapped(buffer);

    final switch (workload)
    {
        case "index":
            return bench_tailroom_index(buffer, operations, rounds);
        case "pushpop":
            return bench_tailroom_pushpop(buffer, operations, rounds);
        case "segments":
            return bench_tailroom_segments(buffer, operations, rounds);
        case "mixed":
            return bench_tailroom_mixed(buffer, operations, rounds);
    }
}

private ulong runAddCarry(
    string workload,
    size_t capacity,
    scope const Operation[] operations,
    size_t rounds)
{
    auto buffer = AddCarryProbe(capacity);
    prepareWrapped(buffer);

    final switch (workload)
    {
        case "index":
            return bench_addcarry_index(buffer, operations, rounds);
        case "pushpop":
            return bench_addcarry_pushpop(buffer, operations, rounds);
        case "segments":
            return bench_addcarry_segments(buffer, operations, rounds);
        case "mixed":
            return bench_addcarry_mixed(buffer, operations, rounds);
    }
}

void main(string[] args)
{
    if (args.length != 5)
    {
        stderr.writeln(
            "usage: runtime-ring-buffer-operation-probe ",
            "<actual|tailroom|addcarry> ",
            "<index|pushpop|segments|mixed> <capacity> <rounds>");
        return;
    }

    const variant = args[1];
    const workload = args[2];
    const capacity = to!size_t(args[3]);
    const rounds = to!size_t(args[4]);

    if (capacity < 3)
    {
        stderr.writeln("capacity must be at least 3");
        return;
    }

    Operation[operationCount] operations = void;
    fillOperations(operations, capacity);

    ulong checksum;

    final switch (variant)
    {
        case "actual":
            checksum = runActual(workload, capacity, operations[], rounds);
            break;
        case "tailroom":
            checksum = runTailRoom(workload, capacity, operations[], rounds);
            break;
        case "addcarry":
            checksum = runAddCarry(workload, capacity, operations[], rounds);
            break;
    }

    writeln(variant, "-", workload, "-", capacity, " ", checksum);
}
