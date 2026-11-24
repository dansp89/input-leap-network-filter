// SPDX-License-Identifier: MIT
//
// LD_PRELOAD interposer for QNetworkInterface::allAddresses().
//
// Strategy (evolved from the reference implementation validated on
// Ubuntu 22.04 / Qt 6.2.4):
//   1. Resolve the real Qt implementation with dlsym(RTLD_NEXT, ...) and call
//      it, so Qt's own semantics (skipping interfaces that are down, IPv4 and
//      IPv6 ordering, scope ids, duplicates) are preserved exactly.
//   2. Compute the set of addresses that belong *only* to filtered
//      interfaces and drop those from the result. An address that is also
//      configured on a kept interface is never removed.
//   3. If anything is wrong (invalid config, disabled, real symbol missing,
//      Qt major mismatch) behave exactly like the original function.
//
// The library also removes itself from LD_PRELOAD as soon as it is loaded, so
// child processes started by the GUI (input-leaps / input-leapc) do not
// inherit it.
#include "ilnf/config.hpp"

#include <QHostAddress>
#include <QList>
#include <QSet>
#include <QNetworkInterface>
#include <QString>
#include <QtGlobal>

#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {

using AllAddressesFn = QList<QHostAddress> (*)();

constexpr const char *kSymbol = "_ZN17QNetworkInterface12allAddressesEv";

void logMsg(const ilnf::Config &cfg, ilnf::LogLevel lvl, const std::string &msg)
{
    const bool forced = std::getenv("ILNF_DEBUG") != nullptr;
    if (!forced && (!cfg.logging || lvl > cfg.level))
        return;
    std::fprintf(stderr, "[input-leap-network-filter] %s\n", msg.c_str());
}

AllAddressesFn realAllAddresses()
{
    static AllAddressesFn fn = reinterpret_cast<AllAddressesFn>(dlsym(RTLD_NEXT, kSymbol));
    return fn;
}

bool qtMajorMatches()
{
    const char *v = qVersion();
    return v && std::atoi(v) == QT_VERSION_MAJOR;
}

// Remove every LD_PRELOAD entry that points at this library.
void stripSelfFromPreload()
{
    if (std::getenv("ILNF_KEEP_PRELOAD"))
        return;
    const char *cur = std::getenv("LD_PRELOAD");
    if (!cur || !*cur)
        return;

    Dl_info info{};
    if (!dladdr(reinterpret_cast<void *>(&stripSelfFromPreload), &info) || !info.dli_fname)
        return;
    const std::string self = info.dli_fname;
    const char *slash = std::strrchr(info.dli_fname, '/');
    const std::string selfBase = slash ? slash + 1 : self;

    std::string in = cur, out;
    size_t pos = 0;
    while (pos <= in.size()) {
        size_t end = in.find_first_of(": ", pos);
        if (end == std::string::npos)
            end = in.size();
        std::string entry = in.substr(pos, end - pos);
        const char *eslash = std::strrchr(entry.c_str(), '/');
        const std::string base = eslash ? eslash + 1 : entry;
        if (!entry.empty() && entry != self && base != selfBase) {
            if (!out.empty())
                out += ':';
            out += entry;
        }
        pos = end + 1;
    }
    if (out.empty())
        unsetenv("LD_PRELOAD");
    else
        setenv("LD_PRELOAD", out.c_str(), 1);
}

__attribute__((constructor)) void ilnfInit()
{
    stripSelfFromPreload();
}

} // namespace

QList<QHostAddress> QNetworkInterface::allAddresses()
{
    AllAddressesFn real = realAllAddresses();
    if (!real) {
        // Should never happen when preloaded into a Qt Network process; fall
        // back to an equivalent of Qt's implementation.
        QList<QHostAddress> r;
        for (const QNetworkInterface &iface : QNetworkInterface::allInterfaces()) {
            if (!(iface.flags() & QNetworkInterface::IsUp))
                continue;
            for (const QNetworkAddressEntry &e : iface.addressEntries())
                r.append(e.ip());
        }
        return r;
    }

    QList<QHostAddress> original = real();

    if (std::getenv("ILNF_DISABLE"))
        return original;

    const ilnf::Config cfg = ilnf::loadConfig(ilnf::configPath());
    if (!cfg.valid) {
        for (const auto &e : cfg.errors)
            std::fprintf(stderr, "[input-leap-network-filter] config error: %s (filter disabled)\n", e.c_str());
        return original;
    }
    if (!cfg.enabled || cfg.mode == ilnf::Mode::Off)
        return original;
    if (!qtMajorMatches()) {
        logMsg(cfg, ilnf::LogLevel::Error, "Qt major version mismatch, filter disabled");
        return original;
    }

    QSet<QHostAddress> hidden, kept;
    for (const QNetworkInterface &iface : QNetworkInterface::allInterfaces()) {
        const bool loopback = iface.flags() & QNetworkInterface::IsLoopBack;
        const ilnf::Verdict v = ilnf::decide(cfg, iface.name().toStdString(), loopback);
        QSet<QHostAddress> &bucket = v.decision == ilnf::Decision::Filter ? hidden : kept;
        for (const QNetworkAddressEntry &e : iface.addressEntries())
            bucket.insert(e.ip());
        if (v.decision == ilnf::Decision::Filter)
            logMsg(cfg, ilnf::LogLevel::Debug,
                   "hiding " + iface.name().toStdString() + " (" + v.reason + ")");
    }
    if (hidden.isEmpty())
        return original;

    QList<QHostAddress> result;
    result.reserve(original.size());
    for (const QHostAddress &a : original) {
        if (hidden.contains(a) && !kept.contains(a))
            continue;
        result.append(a);
    }
    logMsg(cfg, ilnf::LogLevel::Info,
           "allAddresses: " + std::to_string(original.size()) + " -> " + std::to_string(result.size()));
    return result;
}
