// SPDX-License-Identifier: MIT
// Measures the cost of the filtering decision for N synthetic interfaces.
// It does not create interfaces and does not touch the network.
#include "ilnf/config.hpp"

#include <chrono>
#include <cstdio>
#include <string>
#include <vector>

int main()
{
    const ilnf::Config cfg = ilnf::defaultConfig();
    const char *prefixes[] = {"veth", "br-", "docker", "lxcbr", "enp", "wlp", "wg", "tun"};
    std::printf("%-10s %-14s %-14s\n", "ifaces", "total_us", "ns_per_iface");
    for (int n : {10, 50, 100, 500, 1000}) {
        std::vector<std::string> names;
        for (int i = 0; i < n; ++i)
            names.push_back(std::string(prefixes[i % 8]) + std::to_string(i));
        const int reps = 2000;
        volatile int hidden = 0;
        auto t0 = std::chrono::steady_clock::now();
        for (int r = 0; r < reps; ++r)
            for (const auto &nm : names)
                hidden += ilnf::decide(cfg, nm).decision == ilnf::Decision::Filter;
        auto t1 = std::chrono::steady_clock::now();
        double us = std::chrono::duration<double, std::micro>(t1 - t0).count() / reps;
        std::printf("%-10d %-14.2f %-14.1f\n", n, us, us * 1000.0 / n);
    }
    return 0;
}
