#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string_view>

namespace {
constexpr std::size_t value_count = 256;

struct PlainValue {
    std::uint64_t a{};
    std::uint64_t b{};
    std::uint64_t c{};
    std::uint64_t d{};

    PlainValue() noexcept = default;

    explicit PlainValue(std::uint64_t seed) noexcept
        : a(seed),
          b(seed ^ 0x9E3779B97F4A7C15ULL),
          c(seed * 0xD6E8FEB86659FD93ULL),
          d(~seed) {}

    std::uint64_t checksum() const noexcept {
        return (a * 3) ^ (b * 5) ^ (c * 7) ^ (d * 11);
    }
};

void fill_values(std::array<PlainValue, value_count>& values) noexcept
{
    for (std::size_t i = 0; i < values.size(); ++i)
        values[i] = PlainValue(static_cast<std::uint64_t>(i) + 1);
}
}

extern "C" __attribute__((noinline))
std::uint64_t bench_cpp(
    PlainValue* values,
    std::size_t count,
    std::size_t rounds) noexcept
{
    alignas(PlainValue) std::byte raw[sizeof(PlainValue)];
    auto* target = reinterpret_cast<PlainValue*>(raw);

    std::uint64_t checksum = 0;
    std::size_t round = 0;

    while (round < rounds)
    {
        std::size_t i = 0;
        while (i < count)
        {
            auto* placed = std::construct_at(target, values[i]);
            checksum += placed->checksum();
            std::destroy_at(placed);
            ++i;
        }
        ++round;
    }

    return checksum;
}

int main(int argc, char** argv)
{
    if (argc != 2)
        return 2;

    std::array<PlainValue, value_count> values = [] {
        std::array<PlainValue, value_count> result{
            PlainValue(1)
        };
        for (std::size_t i = 0; i < result.size(); ++i)
            result[i] = PlainValue(static_cast<std::uint64_t>(i) + 1);
        return result;
    }();

    const auto rounds =
        static_cast<std::size_t>(std::strtoull(argv[1], nullptr, 10));

    std::cout << "cpp "
              << bench_cpp(values.data(), values.size(), rounds)
              << '\n';
    return 0;
}
