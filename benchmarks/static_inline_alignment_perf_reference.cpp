// Issue #31 stage-A C++ reference for inline slot addressing.
//
// The native representation is the performance reference. The dynamic
// representation mirrors the DMD candidate's slack + runtime-aligned base so
// we can distinguish algorithmic cost from language/frontend cost.

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <new>
#include <string_view>

namespace {

constexpr std::size_t slot_count = 16;
constexpr std::size_t index_count = 256;

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

constexpr std::uint64_t slot_value(std::size_t index) noexcept {
    return (static_cast<std::uint64_t>(index) + 1) *
               0x9E3779B97F4A7C15ULL ^
           0xD6E8FEB86659FD93ULL;
}

void fill_indices(std::array<std::uint8_t, index_count>& indices) noexcept {
    std::uint64_t state = 0xA0761D6478BD642FULL;

    for (std::size_t i = 0; i < indices.size(); ++i) {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        indices[i] = static_cast<std::uint8_t>(
            (state ^ static_cast<std::uint64_t>(i)) & (slot_count - 1));
    }
}

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

using NormalNative = NativeStorage<NormalValue, slot_count>;
using OverNative = NativeStorage<OverAlignedValue, slot_count>;
using OverDynamic = DynamicStorage<OverAlignedValue, slot_count>;

template <class Storage, class Value>
void initialize(Storage& storage) noexcept {
    for (std::size_t i = 0; i < slot_count; ++i)
        std::construct_at(storage.slot(i), slot_value(i));
}

template <class Storage>
void finish(Storage& storage) noexcept {
    for (std::size_t i = 0; i < slot_count; ++i)
        std::destroy_at(storage.slot(i));
}

} // namespace

extern "C" __attribute__((noinline))
std::uint64_t bench_normal_native(
    NormalNative* storage,
    const std::uint8_t* indices,
    std::size_t count,
    std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;

    for (std::size_t round = 0; round < rounds; ++round)
        for (std::size_t i = 0; i < count; ++i)
            checksum += storage->slot(indices[i])->value;

    return checksum;
}

extern "C" __attribute__((noinline))
std::uint64_t bench_over_native(
    OverNative* storage,
    const std::uint8_t* indices,
    std::size_t count,
    std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;

    for (std::size_t round = 0; round < rounds; ++round)
        for (std::size_t i = 0; i < count; ++i)
            checksum += storage->slot(indices[i])->value;

    return checksum;
}

extern "C" __attribute__((noinline))
std::uint64_t bench_over_dynamic(
    OverDynamic* storage,
    const std::uint8_t* indices,
    std::size_t count,
    std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;

    for (std::size_t round = 0; round < rounds; ++round)
        for (std::size_t i = 0; i < count; ++i)
            checksum += storage->slot(indices[i])->value;

    return checksum;
}

int main(int argc, char** argv)
{
    if (argc != 3) {
        std::cerr
            << "usage: static-inline-alignment-perf-reference "
               "<normal|native|dynamic> <rounds>\n";
        return 2;
    }

    const std::string_view variant = argv[1];
    const auto rounds =
        static_cast<std::size_t>(std::strtoull(argv[2], nullptr, 10));

    std::array<std::uint8_t, index_count> indices{};
    fill_indices(indices);

    std::uint64_t checksum = 0;

    if (variant == "normal") {
        NormalNative storage;
        initialize<NormalNative, NormalValue>(storage);
        checksum = bench_normal_native(
            &storage, indices.data(), indices.size(), rounds);
        finish(storage);
    } else if (variant == "native") {
        OverNative storage;
        initialize<OverNative, OverAlignedValue>(storage);
        checksum = bench_over_native(
            &storage, indices.data(), indices.size(), rounds);
        finish(storage);
    } else if (variant == "dynamic") {
        OverDynamic storage;
        initialize<OverDynamic, OverAlignedValue>(storage);
        checksum = bench_over_dynamic(
            &storage, indices.data(), indices.size(), rounds);
        finish(storage);
    } else {
        std::cerr << "unknown variant\n";
        return 2;
    }

    std::cout << variant << ' ' << checksum << '\n';
    return 0;
}
