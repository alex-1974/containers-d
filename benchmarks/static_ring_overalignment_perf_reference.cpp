// Issue #31 stage-B C++ reference for production-shaped static ring
// operations. Native and dynamic storage variants share identical ring
// semantics and operation order.

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string_view>

namespace {

constexpr std::size_t capacity = 16;
constexpr std::size_t value_count = 256;

struct NormalValue {
    std::uint64_t value;
    explicit NormalValue(std::uint64_t v) noexcept : value(v) {}
};

struct alignas(64) OverAlignedValue {
    std::uint64_t value;
    std::array<std::byte, 56> padding{};
    explicit OverAlignedValue(std::uint64_t v) noexcept : value(v) {}
};

static_assert(alignof(OverAlignedValue) == 64);
static_assert(sizeof(OverAlignedValue) == 64);

template <class T, std::size_t N>
struct NativeStorage {
    alignas(T) std::array<std::byte, sizeof(T) * N> bytes;

    T* slot(std::size_t index) noexcept {
        return reinterpret_cast<T*>(bytes.data() + index * sizeof(T));
    }
};

template <class T, std::size_t N>
struct DynamicStorage {
    std::array<std::byte, sizeof(T) * N + alignof(T) - 1> bytes;

    T* slot(std::size_t index) noexcept {
        auto address = reinterpret_cast<std::uintptr_t>(bytes.data());
        const auto mask = static_cast<std::uintptr_t>(alignof(T) - 1);
        const auto misalignment = address & mask;
        const auto offset = (alignof(T) - misalignment) & mask;

        return reinterpret_cast<T*>(
            bytes.data() + offset + index * sizeof(T));
    }
};

template <class T, std::size_t N, class Storage>
class StaticRing {
public:
    StaticRing() = default;

    StaticRing(const StaticRing&) = delete;
    StaticRing& operator=(const StaticRing&) = delete;

    ~StaticRing() {
        while (length_ != 0)
            pop_front();
    }

    bool try_push_back(const T& value) noexcept {
        if (length_ == N)
            return false;

        const auto index = physical_index(length_);
        std::construct_at(storage_.slot(index), value);
        ++length_;
        return true;
    }

    void pop_front() noexcept {
        std::destroy_at(storage_.slot(head_));
        --length_;

        if (length_ == 0) {
            head_ = 0;
        } else {
            ++head_;
            if (head_ == N)
                head_ = 0;
        }
    }

    T& front() noexcept {
        return *storage_.slot(head_);
    }

    T& back() noexcept {
        return *storage_.slot(physical_index(length_ - 1));
    }

    T& operator[](std::size_t logical_index) noexcept {
        return *storage_.slot(physical_index(logical_index));
    }

private:
    std::size_t physical_index(std::size_t logical_index) const noexcept {
        static_assert((N & (N - 1)) == 0);
        return (head_ + logical_index) & (N - 1);
    }

    Storage storage_{};
    std::size_t head_ = 0;
    std::size_t length_ = 0;
};

using NormalNativeRing =
    StaticRing<NormalValue, capacity, NativeStorage<NormalValue, capacity>>;
using OverNativeRing =
    StaticRing<OverAlignedValue, capacity,
        NativeStorage<OverAlignedValue, capacity>>;
using OverDynamicRing =
    StaticRing<OverAlignedValue, capacity,
        DynamicStorage<OverAlignedValue, capacity>>;

void fill_values(std::array<std::uint64_t, value_count>& values) noexcept {
    std::uint64_t state = 0xA0761D6478BD642FULL;

    for (std::size_t i = 0; i < values.size(); ++i) {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        values[i] =
            state ^ (static_cast<std::uint64_t>(i) *
                     0x9E3779B97F4A7C15ULL);
    }
}

template <class Ring, class Value>
void initialize(Ring& ring, const std::array<std::uint64_t, value_count>& values)
{
    for (std::size_t i = 0; i < capacity; ++i) {
        Value value(values[i]);
        if (!ring.try_push_back(value))
            std::abort();
    }
}

template <class Ring, class Value>
std::uint64_t bench_impl(
    Ring& ring,
    const std::array<std::uint64_t, value_count>& values,
    std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;

    for (std::size_t i = 0; i < rounds; ++i) {
        const auto logical_index = (i * 5) & (capacity - 1);

        checksum += ring.front().value * 3;
        checksum ^= ring.back().value * 5;
        checksum += ring[logical_index].value * 7;

        ring.pop_front();

        Value incoming(
            values[(i * 13) & (value_count - 1)] ^
            static_cast<std::uint64_t>(i));

        if (!ring.try_push_back(incoming))
            checksum ^= 0xBAD0BAD0BAD0BAD0ULL;
    }

    checksum ^= ring.front().value;
    checksum += ring.back().value;
    return checksum;
}

} // namespace

extern "C" __attribute__((noinline))
std::uint64_t bench_ring_normal_native(
    NormalNativeRing* ring,
    const std::array<std::uint64_t, value_count>* values,
    std::size_t rounds) noexcept
{
    return bench_impl<NormalNativeRing, NormalValue>(
        *ring, *values, rounds);
}

extern "C" __attribute__((noinline))
std::uint64_t bench_ring_over_native(
    OverNativeRing* ring,
    const std::array<std::uint64_t, value_count>* values,
    std::size_t rounds) noexcept
{
    return bench_impl<OverNativeRing, OverAlignedValue>(
        *ring, *values, rounds);
}

extern "C" __attribute__((noinline))
std::uint64_t bench_ring_over_dynamic(
    OverDynamicRing* ring,
    const std::array<std::uint64_t, value_count>* values,
    std::size_t rounds) noexcept
{
    return bench_impl<OverDynamicRing, OverAlignedValue>(
        *ring, *values, rounds);
}

int main(int argc, char** argv)
{
    if (argc != 3) {
        std::cerr
            << "usage: static-ring-overalignment-perf-reference "
               "<normal|native|dynamic> <rounds>\n";
        return 2;
    }

    const std::string_view variant = argv[1];
    const auto rounds =
        static_cast<std::size_t>(std::strtoull(argv[2], nullptr, 10));

    std::array<std::uint64_t, value_count> values{};
    fill_values(values);

    std::uint64_t checksum = 0;

    if (variant == "normal") {
        NormalNativeRing ring;
        initialize<NormalNativeRing, NormalValue>(ring, values);
        checksum = bench_ring_normal_native(&ring, &values, rounds);
    } else if (variant == "native") {
        OverNativeRing ring;
        initialize<OverNativeRing, OverAlignedValue>(ring, values);
        checksum = bench_ring_over_native(&ring, &values, rounds);
    } else if (variant == "dynamic") {
        OverDynamicRing ring;
        initialize<OverDynamicRing, OverAlignedValue>(ring, values);
        checksum = bench_ring_over_dynamic(&ring, &values, rounds);
    } else {
        std::cerr << "unknown variant\n";
        return 2;
    }

    std::cout << variant << ' ' << checksum << '\n';
    return 0;
}
