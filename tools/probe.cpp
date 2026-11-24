// SPDX-License-Identifier: MIT
//
// ilnf-probe: Qt-independent helper used by the CLI. It shares the exact
// filtering rules with the preloaded library, so `preview` shows precisely
// what the filter will hide.
//
//   ilnf-probe interfaces [--json] [--config PATH] [--sysfs DIR]
//   ilnf-probe check-config [--json] [--config PATH]
//   ilnf-probe profiles [--json]
//   ilnf-probe match PATTERN NAME
#include "ilnf/config.hpp"
#include "ilnf/interfaces.hpp"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

std::string jsonEscape(const std::string &s)
{
    std::string o;
    for (unsigned char c : s) {
        switch (c) {
        case '"': o += "\\\""; break;
        case '\\': o += "\\\\"; break;
        case '\n': o += "\\n"; break;
        case '\t': o += "\\t"; break;
        default:
            if (c < 0x20) {
                char b[8];
                std::snprintf(b, sizeof b, "\\u%04x", c);
                o += b;
            } else {
                o += static_cast<char>(c);
            }
        }
    }
    return o;
}

std::string jsonArray(const std::vector<std::string> &v)
{
    std::string o = "[";
    for (size_t i = 0; i < v.size(); ++i)
        o += (i ? ",\"" : "\"") + jsonEscape(v[i]) + "\"";
    return o + "]";
}

int usage()
{
    std::fprintf(stderr,
                 "usage: ilnf-probe interfaces|check-config|dump|profiles [--json] [--config PATH] [--sysfs DIR]\n"
                 "       ilnf-probe match PATTERN NAME\n");
    return 2;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 2)
        return usage();
    const std::string cmd = argv[1];
    bool json = false;
    std::string cfgPath = ilnf::configPath();
    std::string sysfs = "/sys/class/net";
    std::vector<std::string> positional;
    for (int i = 2; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--json"))
            json = true;
        else if (!std::strcmp(argv[i], "--config") && i + 1 < argc)
            cfgPath = argv[++i];
        else if (!std::strcmp(argv[i], "--sysfs") && i + 1 < argc)
            sysfs = argv[++i];
        else
            positional.push_back(argv[i]);
    }

    if (cmd == "match") {
        if (positional.size() != 2)
            return usage();
        return ilnf::matches(positional[0], positional[1]) ? 0 : 1;
    }

    if (cmd == "profiles") {
        auto names = ilnf::knownProfiles();
        if (json) {
            std::printf("{");
            for (size_t i = 0; i < names.size(); ++i)
                std::printf("%s\"%s\":%s", i ? "," : "", names[i].c_str(),
                            jsonArray(ilnf::profilePatterns(names[i])).c_str());
            std::printf("}\n");
        } else {
            for (const auto &n : names) {
                std::printf("%-12s", n.c_str());
                for (const auto &p : ilnf::profilePatterns(n))
                    std::printf(" %s", p.c_str());
                std::printf("\n");
            }
        }
        return 0;
    }

    const ilnf::Config cfg = ilnf::loadConfig(cfgPath);

    if (cmd == "dump") {
        // Machine-readable effective configuration, one value per line.
        std::printf("valid\t%s\nenabled\t%s\nmode\t%s\n", cfg.valid ? "true" : "false",
                    cfg.enabled ? "true" : "false", ilnf::modeName(cfg.mode));
        for (const auto &p : cfg.profiles)
            std::printf("profile\t%s\n", p.c_str());
        for (const auto &p : cfg.exclude)
            std::printf("exclude\t%s\n", p.c_str());
        for (const auto &p : cfg.include)
            std::printf("include\t%s\n", p.c_str());
        static const char *lv[] = {"error", "warn", "info", "debug"};
        std::printf("logging\t%s\nlevel\t%s\n", cfg.logging ? "true" : "false",
                    lv[static_cast<int>(cfg.level)]);
        return cfg.valid ? 0 : 1;
    }

    if (cmd == "check-config") {
        if (json) {
            std::printf("{\"path\":\"%s\",\"valid\":%s,\"enabled\":%s,\"mode\":\"%s\",\"profiles\":%s,"
                        "\"exclude\":%s,\"include\":%s,\"errors\":%s,\"warnings\":%s}\n",
                        jsonEscape(cfgPath).c_str(), cfg.valid ? "true" : "false",
                        cfg.enabled ? "true" : "false", ilnf::modeName(cfg.mode),
                        jsonArray(cfg.profiles).c_str(), jsonArray(cfg.exclude).c_str(),
                        jsonArray(cfg.include).c_str(), jsonArray(cfg.errors).c_str(),
                        jsonArray(cfg.warnings).c_str());
        } else {
            for (const auto &e : cfg.errors)
                std::printf("error: %s\n", e.c_str());
            for (const auto &w : cfg.warnings)
                std::printf("warning: %s\n", w.c_str());
            std::printf("%s\n", cfg.valid ? "valid" : "invalid");
        }
        return cfg.valid ? 0 : 1;
    }

    if (cmd == "interfaces") {
        const auto list = ilnf::listInterfaces(sysfs);
        if (json) {
            std::printf("{\"config_valid\":%s,\"interfaces\":[", cfg.valid ? "true" : "false");
            for (size_t i = 0; i < list.size(); ++i) {
                const auto &it = list[i];
                const auto v = ilnf::decide(cfg, it.name, it.kind == "loopback");
                std::printf("%s{\"name\":\"%s\",\"kind\":\"%s\",\"physical\":%s,\"up\":%s,"
                            "\"addresses\":%s,\"filtered\":%s,\"reason\":\"%s\"}",
                            i ? "," : "", jsonEscape(it.name).c_str(), jsonEscape(it.kind).c_str(),
                            it.physical ? "true" : "false", it.up ? "true" : "false",
                            jsonArray(it.addresses).c_str(),
                            v.decision == ilnf::Decision::Filter ? "true" : "false",
                            jsonEscape(v.reason).c_str());
            }
            std::printf("]}\n");
        } else {
            // Tab-separated, consumed by the Bash CLI.
            for (const auto &it : list) {
                const auto v = ilnf::decide(cfg, it.name, it.kind == "loopback");
                std::string addrs;
                for (const auto &a : it.addresses)
                    addrs += (addrs.empty() ? "" : ",") + a;
                std::printf("%s\t%s\t%s\t%s\t%s\t%s\t%s\n", it.name.c_str(), it.kind.c_str(),
                            it.physical ? "physical" : "virtual", it.up ? "up" : "down",
                            v.decision == ilnf::Decision::Filter ? "filter" : "keep", v.reason.c_str(),
                            addrs.empty() ? "-" : addrs.c_str());
            }
        }
        return cfg.valid ? 0 : 1;
    }
    return usage();
}
