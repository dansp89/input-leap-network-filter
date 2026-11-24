// SPDX-License-Identifier: MIT
// Read-only discovery of network interfaces through sysfs and getifaddrs().
// Used by the CLI (`interfaces`, `preview`, `doctor`); never modifies anything.
#pragma once

#include <string>
#include <vector>

namespace ilnf {

struct InterfaceInfo {
    std::string name;
    std::string kind;    // loopback, ethernet, wifi, bridge, veth, tun, wireguard, vlan, virtual, ...
    bool physical = false; // backed by a device (not under /sys/devices/virtual)
    bool up = false;
    std::vector<std::string> addresses; // IPv4 and IPv6, textual
};

// `sysfsRoot` defaults to /sys/class/net; tests point it at fixtures.
std::vector<InterfaceInfo> listInterfaces(const std::string &sysfsRoot = "/sys/class/net",
                                          bool withAddresses = true);

} // namespace ilnf
