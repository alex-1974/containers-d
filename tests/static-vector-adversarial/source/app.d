module app;

import containers.static_vector : StaticVector;

enum size_t capacity = 17;
enum size_t iterations = 100_000;

private struct ReferenceModel
{
    int[capacity] data;
    size_t length;

    @property bool empty() const @safe @nogc nothrow
    {
        return length == 0;
    }

    @property bool full() const @safe @nogc nothrow
    {
        return length == capacity;
    }

    bool tryPushBack(int value) @safe @nogc nothrow
    {
        if (full)
            return false;

        data[length] = value;
        ++length;
        return true;
    }

    void popBack() @safe @nogc nothrow
    {
        assert(!empty);
        --length;
    }

    void clear() @safe @nogc nothrow
    {
        length = 0;
    }
}

private ulong nextRandom(ref ulong state)
    @safe @nogc nothrow
{
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return state;
}

private void verify(
    ref StaticVector!(int, capacity) vector,
    ref const ReferenceModel model)
    @safe @nogc nothrow
{
    assert(vector.capacity == capacity);
    assert(vector.length == model.length);
    assert(vector.empty == model.empty);
    assert(vector.full == model.full);

    auto live = vector[];
    assert(live.length == model.length);

    foreach (index; 0 .. model.length)
        assert(live[index] == model.data[index]);

    if (!model.empty)
    {
        assert(vector.front == model.data[0]);
        assert(vector.back == model.data[model.length - 1]);
    }
}

void main()
{
    StaticVector!(int, capacity) vector;
    ReferenceModel model;

    ulong state = 0xD1B5_4A32_D192_ED03UL;

    verify(vector, model);

    foreach (_; 0 .. iterations)
    {
        const random = nextRandom(state);
        const operation = random % 7;

        final switch (operation)
        {
            case 0:
            case 1:
            {
                const value =
                    cast(int) (random >> 32);

                const actual =
                    vector.tryPushBack(value);
                const expected =
                    model.tryPushBack(value);

                assert(actual == expected);
                break;
            }

            case 2:
                if (!model.empty)
                {
                    vector.popBack();
                    model.popBack();
                }
                break;

            case 3:
                vector.clear();
                model.clear();
                break;

            case 4:
                if (!model.empty)
                {
                    const index =
                        cast(size_t) (
                            (random >> 8) %
                            model.length);

                    const value =
                        cast(int) (random >> 24);

                    vector[index] = value;
                    model.data[index] = value;
                }
                break;

            case 5:
                if (!model.empty)
                {
                    auto live = vector[];

                    const index =
                        cast(size_t) (
                            (random >> 16) %
                            model.length);

                    const value =
                        cast(int) (random >> 28);

                    live[index] = value;
                    model.data[index] = value;
                }
                break;

            case 6:
                // Verify that failed insertion on full is non-mutating.
                if (model.full)
                {
                    const beforeBack = vector.back;
                    const beforeLength = vector.length;

                    assert(!vector.tryPushBack(
                        cast(int) random));

                    assert(vector.length == beforeLength);
                    assert(vector.back == beforeBack);
                }
                break;
        }

        verify(vector, model);
    }

    vector.clear();
    model.clear();
    verify(vector, model);
}
