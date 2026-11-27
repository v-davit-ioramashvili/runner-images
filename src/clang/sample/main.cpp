#include <atomic>
#include <cstdio>
#include <string>
#include <vector>

int main() {
    std::atomic<int> value{41};
    std::vector<std::string> items{"clang", "stl"};
    value.fetch_add(1);
    std::printf("value=%d items=%zu\n", value.load(), items.size());
    return value.load() == 42 && items.size() == 2 ? 0 : 1;
}
