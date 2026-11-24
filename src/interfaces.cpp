// SPDX-License-Identifier: MIT
#include "ilnf/interfaces.hpp"

#include <algorithm>
#include <arpa/inet.h>
#include <climits>
#include <cstdlib>
#include <dirent.h>
#include <fstream>
#include <ifaddrs.h>
#include <map>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/stat.h>
#include <unistd.h>

namespace ilnf {

namespace {

bool exists(const std::string &p)
{
    struct stat st{};
    return ::lstat(p.c_str(), &st) == 0;
}

std::string readFirstLine(const std::string &p)
{
    std::ifstream f(p);
    std::string s;
    std::getline(f, s);
    return s;
}

std::string ueventValue(const std::string &dir, const std::string &key)
{
    std::ifstream f(dir + "/uevent");
    std::string line;
    while (std::getline(f, line))
        if (line.rfind(key + "=", 0) == 0)
            return line.substr(key.size() + 1);
    return {};
}

std::string classify(const std::string &dir, const std::string &name, bool physical)
{
    const std::string type = readFirstLine(dir + "/type");
    if (type == "772" || name == "lo")
        return "loopback";
    if (exists(dir + "/wireless") || exists(dir + "/phy80211"))
        return "wifi";
    const std::string devtype = ueventValue(dir, "DEVTYPE");
    if (!devtype.empty() && devtype != "wlan")
        return devtype; // bridge, vlan, wireguard, bond, ...
    if (exists(dir + "/bridge"))
        return "bridge";
    if (exists(dir + "/tun_flags"))
        return "tun";
    if (physical)
        return "ethernet";
    if (name.rfind("veth", 0) == 0)
        return "veth";
    return "virtual";
}

} // namespace

std::vector<InterfaceInfo> listInterfaces(const std::string &root, bool withAddresses)
{
    std::vector<InterfaceInfo> out;
    DIR *d = ::opendir(root.c_str());
    if (!d)
        return out;
    while (dirent *e = ::readdir(d)) {
        std::string name = e->d_name;
        if (name == "." || name == "..")
            continue;
        const std::string dir = root + "/" + name;
        InterfaceInfo info;
        info.name = name;
        // A physical NIC has a `device` link; virtual ones live under
        // /sys/devices/virtual.
        char buf[PATH_MAX];
        std::string real;
        if (::realpath(dir.c_str(), buf))
            real = buf;
        info.physical = exists(dir + "/device") && real.find("/devices/virtual/") == std::string::npos;
        info.kind = classify(dir, name, info.physical);
        const std::string oper = readFirstLine(dir + "/operstate");
        const std::string flags = readFirstLine(dir + "/flags");
        long fl = flags.empty() ? 0 : std::strtol(flags.c_str(), nullptr, 16);
        info.up = (fl & IFF_UP) != 0 || oper == "up";
        out.push_back(info);
    }
    ::closedir(d);
    std::sort(out.begin(), out.end(),
              [](const InterfaceInfo &a, const InterfaceInfo &b) { return a.name < b.name; });

    if (!withAddresses)
        return out;

    ifaddrs *ifa = nullptr;
    if (::getifaddrs(&ifa) != 0)
        return out;
    std::map<std::string, std::vector<std::string>> addrs;
    for (ifaddrs *p = ifa; p; p = p->ifa_next) {
        if (!p->ifa_addr || !p->ifa_name)
            continue;
        char txt[INET6_ADDRSTRLEN] = {};
        if (p->ifa_addr->sa_family == AF_INET)
            ::inet_ntop(AF_INET, &reinterpret_cast<sockaddr_in *>(p->ifa_addr)->sin_addr, txt, sizeof txt);
        else if (p->ifa_addr->sa_family == AF_INET6)
            ::inet_ntop(AF_INET6, &reinterpret_cast<sockaddr_in6 *>(p->ifa_addr)->sin6_addr, txt, sizeof txt);
        else
            continue;
        addrs[p->ifa_name].push_back(txt);
    }
    ::freeifaddrs(ifa);
    for (auto &i : out)
        i.addresses = addrs[i.name];
    return out;
}

} // namespace ilnf
