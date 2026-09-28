#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string_view>

namespace {
constexpr std::size_t value_count = 16;
constexpr std::size_t index_count = 256;

struct Value { std::uint64_t value; };

constexpr std::uint64_t slot_value(std::size_t index) noexcept
{
    return (static_cast<std::uint64_t>(index) + 1) *
               0x9E3779B97F4A7C15ULL ^
           0xD6E8FEB86659FD93ULL;
}

void fill_values(std::array<Value, value_count>& values) noexcept
{
    for (std::size_t i = 0; i < values.size(); ++i)
        values[i].value = slot_value(i);
}

void fill_indices(std::array<std::uint8_t, index_count>& indices) noexcept
{
    std::uint64_t state = 0xA0761D6478BD642FULL;
    for (std::size_t i = 0; i < indices.size(); ++i)
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        indices[i] = static_cast<std::uint8_t>(
            (state ^ static_cast<std::uint64_t>(i)) & (value_count - 1));
    }
}
}

extern "C" __attribute__((noinline))
std::uint64_t bench_foreach_struct(
    const Value* base, const std::uint8_t* indices,
    std::size_t count, std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;
    for (std::size_t round = 0; round < rounds; ++round)
        for (std::size_t i = 0; i < count; ++i)
            checksum += base[indices[i]].value;
    return checksum;
}

extern "C" __attribute__((noinline))
std::uint64_t bench_while_struct(
    const Value* base, const std::uint8_t* indices,
    std::size_t count, std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;
    std::size_t round = 0;
    while (round < rounds)
    {
        std::size_t i = 0;
        while (i < count)
        {
            checksum += base[indices[i]].value;
            ++i;
        }
        ++round;
    }
    return checksum;
}

extern "C" __attribute__((noinline))
std::uint64_t bench_while_scalar(
    const std::uint64_t* base, const std::uint8_t* indices,
    std::size_t count, std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;
    std::size_t round = 0;
    while (round < rounds)
    {
        std::size_t i = 0;
        while (i < count)
        {
            checksum += base[indices[i]];
            ++i;
        }
        ++round;
    }
    return checksum;
}

extern "C" __attribute__((noinline))
std::uint64_t bench_pointer_indices(
    const std::uint64_t* base, const std::uint8_t* indices,
    std::size_t count, std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;
    std::size_t round = 0;
    while (round < rounds)
    {
        const auto* cursor = indices;
        const auto* end = indices + count;
        while (cursor != end)
        {
            checksum += base[*cursor];
            ++cursor;
        }
        ++round;
    }
    return checksum;
}

extern "C" __attribute__((noinline))
std::uint64_t bench_fixed_count(
    const std::uint64_t* base, const std::uint8_t* indices,
    std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;
    std::size_t round = 0;
    while (round < rounds)
    {
        std::size_t i = 0;
        while (i < index_count)
        {
            checksum += base[indices[i]];
            ++i;
        }
        ++round;
    }
    return checksum;
}

extern "C" __attribute__((noinline))
std::uint64_t bench_unrolled4(
    const std::uint64_t* base, const std::uint8_t* indices,
    std::size_t rounds) noexcept
{
    std::uint64_t checksum = 0;
    std::size_t round = 0;
    while (round < rounds)
    {
        std::size_t i = 0;
        while (i < index_count)
        {
            checksum += base[indices[i]];
            checksum += base[indices[i + 1]];
            checksum += base[indices[i + 2]];
            checksum += base[indices[i + 3]];
            i += 4;
        }
        ++round;
    }
    return checksum;
}

int main(int argc, char** argv)
{
    if (argc != 3)
    {
        std::cerr << "usage: dmd-codegen-reference <variant> <rounds>\n";
        return 2;
    }

    std::array<Value, value_count> values{};
    std::array<std::uint8_t, index_count> indices{};
    fill_values(values);
    fill_indices(indices);

    const auto rounds =
        static_cast<std::size_t>(std::strtoull(argv[2], nullptr, 10));
    const std::string_view variant = argv[1];
    const auto* scalar_base =
        reinterpret_cast<const std::uint64_t*>(values.data());

    std::uint64_t checksum = 0;
    if (variant == "foreach-struct")
        checksum = bench_foreach_struct(values.data(), indices.data(), indices.size(), rounds);
    else if (variant == "while-struct")
        checksum = bench_while_struct(values.data(), indices.data(), indices.size(), rounds);
    else if (variant == "while-scalar")
        checksum = bench_while_scalar(scalar_base, indices.data(), indices.size(), rounds);
    else if (variant == "pointer-indices")
        checksum = bench_pointer_indices(scalar_base, indices.data(), indices.size(), rounds);
    else if (variant == "fixed-count")
        checksum = bench_fixed_count(scalar_base, indices.data(), rounds);
    else if (variant == "unrolled4")
        checksum = bench_unrolled4(scalar_base, indices.data(), rounds);
    else
        return 2;

    std::cout << variant << ' ' << checksum << '\n';
    return 0;
}
