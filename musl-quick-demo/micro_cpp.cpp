// micro_cpp.cpp - does C++ (libstdc++) work on musl, and what does it cost in size?
// exercises: iostream, string, vector+sort, exceptions, std::thread.
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <thread>
#include <stdexcept>

int main(){
    std::vector<int> v{5,3,1,4,2};
    std::sort(v.begin(), v.end());
    std::string s = "cpp.sorted=";
    for (int x : v) s += std::to_string(x);
    std::cout << s << "\n";
    try { throw std::runtime_error("probe"); }
    catch (const std::exception &e) { std::cout << "cpp.exception=OK(" << e.what() << ")\n"; }
    int tv = 0;
    std::thread t([&]{ tv = 42; });
    t.join();
    std::cout << "cpp.thread=" << (tv==42 ? "OK" : "FAIL") << "\n";
    return 0;
}
