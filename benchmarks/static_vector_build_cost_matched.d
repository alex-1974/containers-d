module static_vector_build_cost_matched;

private ulong foldValue(ulong checksum, ulong value)
    pure nothrow @safe @nogc
{
    checksum ^= value + 0x9E37_79B9_7F4A_7C15UL;
    checksum *= 0x0000_0100_0000_01B3UL;
    return checksum;
}

private struct MatchedVector(size_t Capacity)
if (Capacity > 0)
{
    enum size_t capacity = Capacity;

private:
    ulong[Capacity] data;
    size_t _length;

public:
    pragma(inline, true)
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _length;
    }

    pragma(inline, true)
    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _length == 0;
    }

    @property bool full() const
        pure nothrow @safe @nogc
    {
        return _length == Capacity;
    }

    ref ulong front()
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return data[0];
    }

    ref const(ulong) front() const
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return data[0];
    }

    ref ulong back()
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return data[_length - 1];
    }

    ref const(ulong) back() const
        return scope pure nothrow @safe @nogc
    {
        assert(!empty);
        return data[_length - 1];
    }

    pragma(inline, true)
    ref ulong opIndex(size_t index)
        return scope pure nothrow @safe @nogc
    {
        assert(index < _length);
        return data[index];
    }

    pragma(inline, true)
    ref const(ulong) opIndex(size_t index) const
        return scope pure nothrow @safe @nogc
    {
        assert(index < _length);
        return data[index];
    }

    pragma(inline, true)
    ulong[] opSlice()
        return scope pure nothrow @safe @nogc
    {
        return data[0 .. _length];
    }

    pragma(inline, true)
    const(ulong)[] opSlice() const
        return scope pure nothrow @safe @nogc
    {
        return data[0 .. _length];
    }

    pragma(inline, true)
    void pushBack(ulong value)
        pure nothrow @safe @nogc
    {
        assert(!full);
        data[_length] = value;
        ++_length;
    }

    pragma(inline, true)
    bool tryPushBack(ulong value)
        pure nothrow @safe @nogc
    {
        if (full)
            return false;

        data[_length] = value;
        ++_length;
        return true;
    }

    void popBack()
        pure nothrow @safe @nogc
    {
        assert(!empty);
        --_length;
    }

    pragma(inline, true)
    void clear()
        pure nothrow @safe @nogc
    {
        _length = 0;
    }
}

private ulong run(size_t Capacity)(ulong seed)
    pure nothrow @safe @nogc
{
    MatchedVector!Capacity vector;

    static foreach (i; 0 .. Capacity)
        vector.pushBack(seed + i);

    ulong checksum = 0xCBF2_9CE4_8422_2325UL;

    static foreach (i; 0 .. Capacity)
        checksum = foldValue(checksum, vector[i]);

    return checksum;
}

extern(C) ulong matched_1(ulong x) { return run!1(x); }
extern(C) ulong matched_2(ulong x) { return run!2(x); }
extern(C) ulong matched_3(ulong x) { return run!3(x); }
extern(C) ulong matched_4(ulong x) { return run!4(x); }
extern(C) ulong matched_8(ulong x) { return run!8(x); }
extern(C) ulong matched_16(ulong x) { return run!16(x); }
extern(C) ulong matched_32(ulong x) { return run!32(x); }
extern(C) ulong matched_64(ulong x) { return run!64(x); }
