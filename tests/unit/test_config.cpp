// SPDX-License-Identifier: MIT
#include "ilnf/config.hpp"

#include <cstdio>
#include <string>

static int failures = 0;
#define CHECK(cond)                                                              \
    do {                                                                         \
        if (!(cond)) {                                                           \
            std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
            ++failures;                                                          \
        }                                                                        \
    } while (0)

using namespace ilnf;

static bool filtered(const Config &c, const std::string &n, bool lo = false)
{
    return decide(c, n, lo).decision == Decision::Filter;
}

int main()
{
    // Defaults reproduce the validated reference implementation.
    Config d = defaultConfig();
    CHECK(d.valid);
    CHECK(filtered(d, "docker0"));
    CHECK(filtered(d, "br-1a2b3c"));
    CHECK(filtered(d, "veth12ab"));
    CHECK(filtered(d, "lxcbr0"));
    CHECK(!filtered(d, "eth0"));
    CHECK(!filtered(d, "enp3s0"));
    CHECK(!filtered(d, "wlp2s0"));
    CHECK(!filtered(d, "lo", true));
    // VPNs / tunnels are never hidden by default.
    CHECK(!filtered(d, "wg0"));
    CHECK(!filtered(d, "tailscale0"));
    CHECK(!filtered(d, "ztabcdef"));
    CHECK(!filtered(d, "tun0"));
    CHECK(!filtered(d, "virbr0")); // libvirt profile is opt-in

    // Full config parsing, multi-line arrays, comments.
    Config c = parseConfig(R"(
# comment
[filter]
enabled = true
mode = "denylist"   # inline comment

[interfaces]
profiles = ["docker", "libvirt"]
exclude = [
    "custom*",
    "eth9",
]
include = ["br-keep"]

[logging]
enabled = false
level = "debug"
)");
    CHECK(c.valid);
    CHECK(c.level == LogLevel::Debug);
    CHECK(filtered(c, "virbr0"));
    CHECK(filtered(c, "custom1"));
    CHECK(filtered(c, "eth9"));
    CHECK(!filtered(c, "eth90"));       // exact match is exact
    CHECK(!filtered(c, "br-keep"));     // allowlist wins over profile
    CHECK(filtered(c, "br-other"));
    CHECK(!filtered(c, "lxcbr0"));      // profiles replaced defaults

    // Allowlist mode: only included interfaces, loopback preserved.
    Config a = parseConfig("[filter]\nmode = \"allowlist\"\n[interfaces]\ninclude = [\"en*\", \"wl*\"]\n");
    CHECK(a.valid);
    CHECK(!filtered(a, "enp3s0"));
    CHECK(filtered(a, "docker0"));
    CHECK(filtered(a, "wg0"));
    CHECK(!filtered(a, "lo", true));

    // Explicit exclusion of loopback in denylist mode works.
    Config l = parseConfig("[interfaces]\nexclude = [\"lo\"]\n");
    CHECK(filtered(l, "lo", true));

    // Disabled / off.
    CHECK(!filtered(parseConfig("[filter]\nenabled = false\n"), "docker0"));
    CHECK(!filtered(parseConfig("[filter]\nmode = \"off\"\n"), "docker0"));

    // Invalid configs never filter (safe pass-through).
    const char *bad[] = {
        "[filter]\nenabled = yes\n",
        "[filter]\nmode = \"weird\"\n",
        "[interfaces]\nexclude = \"docker*\"\n",
        "[interfaces]\nexclude = [\"$(rm -rf ~)\"]\n",
        "[interfaces]\nexclude = [\"../../etc\"]\n",
        "[interfaces]\nprofiles = [\"nope\"]\n",
        "garbage line\n",
    };
    for (const char *b : bad) {
        Config x = parseConfig(b);
        CHECK(!x.valid);
        CHECK(!x.errors.empty());
        CHECK(!filtered(x, "docker0"));
    }

    // Unknown keys are warnings, not errors.
    Config w = parseConfig("[filter]\nfoo = 1\n");
    CHECK(w.valid);
    CHECK(!w.warnings.empty());

    // Glob features.
    CHECK(matches("veth*", "veth0"));
    CHECK(matches("eth[0-3]", "eth2"));
    CHECK(!matches("eth[0-3]", "eth5"));
    CHECK(matches("tap?", "tap1"));
    CHECK(validPattern("cni-podman*"));
    CHECK(!validPattern(""));
    CHECK(!validPattern("a b"));
    CHECK(!validPattern(std::string(65, 'a')));

    if (failures)
        std::fprintf(stderr, "%d failure(s)\n", failures);
    else
        std::printf("all config tests passed\n");
    return failures ? 1 : 0;
}
