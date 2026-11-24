// SPDX-License-Identifier: MIT
#include "ilnf/config.hpp"

#include <cctype>
#include <cstdlib>
#include <fnmatch.h>
#include <fstream>
#include <map>
#include <sstream>
#include <unistd.h>

namespace ilnf {

namespace {

const std::map<std::string, std::vector<std::string>> &profileTable()
{
    static const std::map<std::string, std::vector<std::string>> table = {
        {"docker", {"docker*", "br-*", "veth*"}},
        {"lxc", {"lxcbr*"}},
        {"lxd", {"lxdbr*"}},
        {"incus", {"incusbr*"}},
        {"podman", {"podman*", "cni-podman*"}},
        {"kubernetes", {"cni*", "flannel*", "cali*", "kube-ipvs*"}},
        {"libvirt", {"virbr*", "vnet*"}},
        {"openvswitch", {"ovs-*"}},
    };
    return table;
}

std::string trim(const std::string &s)
{
    size_t b = 0, e = s.size();
    while (b < e && std::isspace(static_cast<unsigned char>(s[b])))
        ++b;
    while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1])))
        --e;
    return s.substr(b, e - b);
}

// Remove a trailing comment that is not inside a string.
std::string stripComment(const std::string &line)
{
    bool inStr = false;
    for (size_t i = 0; i < line.size(); ++i) {
        char c = line[i];
        if (c == '"' && (i == 0 || line[i - 1] != '\\'))
            inStr = !inStr;
        else if (c == '#' && !inStr)
            return line.substr(0, i);
    }
    return line;
}

bool parseString(const std::string &v, std::string &out)
{
    if (v.size() < 2 || v.front() != '"' || v.back() != '"')
        return false;
    std::string body = v.substr(1, v.size() - 2);
    // Escapes and embedded quotes are not needed for interface names.
    if (body.find('"') != std::string::npos || body.find('\\') != std::string::npos)
        return false;
    out = body;
    return true;
}

bool parseArray(const std::string &v, std::vector<std::string> &out)
{
    if (v.size() < 2 || v.front() != '[' || v.back() != ']')
        return false;
    std::string body = trim(v.substr(1, v.size() - 2));
    out.clear();
    if (body.empty())
        return true;
    std::stringstream ss(body);
    std::string item;
    while (std::getline(ss, item, ',')) {
        item = trim(item);
        if (item.empty())
            continue; // trailing comma
        std::string s;
        if (!parseString(item, s))
            return false;
        out.push_back(s);
    }
    return true;
}

bool parseBool(const std::string &v, bool &out)
{
    if (v == "true") {
        out = true;
        return true;
    }
    if (v == "false") {
        out = false;
        return true;
    }
    return false;
}

} // namespace

std::vector<std::string> knownProfiles()
{
    std::vector<std::string> r;
    for (const auto &kv : profileTable())
        r.push_back(kv.first);
    return r;
}

std::vector<std::string> profilePatterns(const std::string &profile)
{
    auto it = profileTable().find(profile);
    return it == profileTable().end() ? std::vector<std::string>{} : it->second;
}

std::vector<std::string> Config::denyPatterns() const
{
    std::vector<std::string> r;
    for (const auto &p : profiles)
        for (const auto &pat : profilePatterns(p))
            r.push_back(pat);
    for (const auto &e : exclude)
        r.push_back(e);
    return r;
}

Config defaultConfig()
{
    Config c;
    c.profiles = {"docker", "lxc"};
    return c;
}

bool validPattern(const std::string &p)
{
    if (p.empty() || p.size() > 64)
        return false;
    for (unsigned char ch : p) {
        if (std::isalnum(ch))
            continue;
        switch (ch) {
        case '_': case '.': case ':': case '@': case '-':
        case '*': case '?': case '!': case '[': case ']':
            continue;
        default:
            return false;
        }
    }
    return true;
}

Config parseConfig(const std::string &text)
{
    Config c = defaultConfig();
    std::string section;
    std::stringstream in(text);
    std::string raw;
    int lineNo = 0;

    auto fail = [&](const std::string &msg) {
        c.valid = false;
        c.errors.push_back("line " + std::to_string(lineNo) + ": " + msg);
    };

    while (std::getline(in, raw)) {
        ++lineNo;
        std::string line = trim(stripComment(raw));
        if (line.empty())
            continue;

        if (line.front() == '[' && line.back() == ']' && line.find('=') == std::string::npos) {
            section = trim(line.substr(1, line.size() - 2));
            if (section != "filter" && section != "interfaces" && section != "logging")
                c.warnings.push_back("line " + std::to_string(lineNo) + ": unknown section [" + section + "]");
            continue;
        }

        auto eq = line.find('=');
        if (eq == std::string::npos) {
            fail("expected key = value");
            continue;
        }
        std::string key = trim(line.substr(0, eq));
        std::string value = trim(line.substr(eq + 1));

        // Multi-line arrays: keep reading until the closing bracket.
        if (!value.empty() && value.front() == '[') {
            while (value.find(']') == std::string::npos && std::getline(in, raw)) {
                ++lineNo;
                value += " " + trim(stripComment(raw));
            }
            value = trim(value);
        }

        const std::string full = section + "." + key;
        if (full == "filter.enabled") {
            if (!parseBool(value, c.enabled))
                fail("filter.enabled must be true or false");
        } else if (full == "filter.mode") {
            std::string m;
            if (!parseString(value, m))
                fail("filter.mode must be a string");
            else if (m == "denylist")
                c.mode = Mode::Denylist;
            else if (m == "allowlist")
                c.mode = Mode::Allowlist;
            else if (m == "off")
                c.mode = Mode::Off;
            else
                fail("filter.mode must be \"denylist\", \"allowlist\" or \"off\"");
        } else if (full == "interfaces.exclude" || full == "interfaces.include" ||
                   full == "interfaces.profiles") {
            std::vector<std::string> items;
            if (!parseArray(value, items)) {
                fail(full + " must be an array of strings");
                continue;
            }
            bool isProfiles = full == "interfaces.profiles";
            for (const auto &it : items) {
                if (isProfiles) {
                    if (profilePatterns(it).empty())
                        fail("unknown profile \"" + it + "\"");
                } else if (!validPattern(it)) {
                    fail("invalid interface pattern \"" + it + "\"");
                }
            }
            if (full == "interfaces.exclude")
                c.exclude = items;
            else if (full == "interfaces.include")
                c.include = items;
            else
                c.profiles = items;
        } else if (full == "logging.enabled") {
            if (!parseBool(value, c.logging))
                fail("logging.enabled must be true or false");
        } else if (full == "logging.level") {
            std::string l;
            if (!parseString(value, l))
                fail("logging.level must be a string");
            else if (l == "error")
                c.level = LogLevel::Error;
            else if (l == "warn")
                c.level = LogLevel::Warn;
            else if (l == "info")
                c.level = LogLevel::Info;
            else if (l == "debug")
                c.level = LogLevel::Debug;
            else
                fail("logging.level must be error, warn, info or debug");
        } else {
            c.warnings.push_back("line " + std::to_string(lineNo) + ": unknown key " + full);
        }
    }
    return c;
}

Config loadConfig(const std::string &path)
{
    if (path.empty() || ::access(path.c_str(), F_OK) != 0)
        return defaultConfig(); // no config file: built-in defaults
    std::ifstream f(path);
    if (!f.is_open()) {
        Config c;
        c.valid = false;
        c.errors.push_back("cannot open " + path);
        return c;
    }
    std::stringstream ss;
    ss << f.rdbuf();
    if (f.bad()) {
        Config c;
        c.valid = false;
        c.errors.push_back("cannot read " + path);
        return c;
    }
    return parseConfig(ss.str());
}

std::string configPath()
{
    if (const char *p = std::getenv("ILNF_CONFIG"); p && *p)
        return p;
    if (const char *x = std::getenv("XDG_CONFIG_HOME"); x && *x == '/')
        return std::string(x) + "/input-leap-network-filter/config.toml";
    if (const char *h = std::getenv("HOME"); h && *h)
        return std::string(h) + "/.config/input-leap-network-filter/config.toml";
    return {};
}

bool matches(const std::string &pattern, const std::string &name)
{
    return fnmatch(pattern.c_str(), name.c_str(), 0) == 0;
}

Verdict decide(const Config &cfg, const std::string &name, bool loopback)
{
    if (!cfg.valid || !cfg.enabled || cfg.mode == Mode::Off)
        return {Decision::Keep, cfg.valid ? "disabled" : "invalid-config"};

    for (const auto &p : cfg.include)
        if (matches(p, name))
            return {Decision::Keep, "include:" + p};

    if (cfg.mode == Mode::Allowlist)
        return loopback ? Verdict{Decision::Keep, "loopback"}
                        : Verdict{Decision::Filter, "allowlist:not-included"};

    for (const auto &p : cfg.denyPatterns())
        if (matches(p, name))
            return {Decision::Filter, "exclude:" + p};

    return {Decision::Keep, "default"};
}

const char *modeName(Mode m)
{
    switch (m) {
    case Mode::Denylist: return "denylist";
    case Mode::Allowlist: return "allowlist";
    case Mode::Off: return "off";
    }
    return "?";
}

} // namespace ilnf
