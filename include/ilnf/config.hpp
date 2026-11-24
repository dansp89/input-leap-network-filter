// SPDX-License-Identifier: MIT
// Input Leap Network Filter - configuration model and filtering rules.
//
// This header is Qt-independent on purpose: the same rules are used by the
// LD_PRELOAD library, by the `ilnf-probe` helper used by the CLI, and by the
// unit tests, so there is a single source of truth for "is this interface
// filtered?".
#pragma once

#include <string>
#include <vector>

namespace ilnf {

enum class Mode {
    Denylist,  // hide interfaces matching `exclude` (unless in `include`)
    Allowlist, // show only interfaces matching `include`
    Off,       // never hide anything (original Qt behaviour)
};

enum class LogLevel { Error = 0, Warn = 1, Info = 2, Debug = 3 };

struct Config {
    bool enabled = true;
    Mode mode = Mode::Denylist;
    std::vector<std::string> profiles;  // names of predefined pattern sets
    std::vector<std::string> exclude;   // user deny patterns (glob / exact)
    std::vector<std::string> include;   // allow patterns, always win
    bool logging = false;
    LogLevel level = LogLevel::Warn;

    // Parse diagnostics. When `valid` is false the caller must fall back to
    // the original Qt behaviour (pass-through) so Input Leap keeps working.
    bool valid = true;
    std::vector<std::string> errors;
    std::vector<std::string> warnings;

    // Effective deny patterns: expanded profiles + exclude.
    std::vector<std::string> denyPatterns() const;
};

enum class Decision { Keep, Filter };

struct Verdict {
    Decision decision = Decision::Keep;
    std::string reason; // e.g. "include:wlan*", "exclude:docker*", "default"
};

// Built-in configuration used when no config file exists. Matches the
// reference implementation validated on Ubuntu 22.04 (docker*, br-*, veth*,
// lxcbr*).
Config defaultConfig();

// Parse the supported TOML subset (see docs/configuration.md).
Config parseConfig(const std::string &text);

// Load from a path. A missing file yields defaultConfig(); an unreadable or
// invalid file yields a Config with valid=false.
Config loadConfig(const std::string &path);

// Resolve the configuration path: $ILNF_CONFIG, then
// $XDG_CONFIG_HOME/input-leap-network-filter/config.toml, then
// $HOME/.config/input-leap-network-filter/config.toml.
std::string configPath();

// Patterns of a predefined profile; empty if the profile is unknown.
std::vector<std::string> profilePatterns(const std::string &profile);
std::vector<std::string> knownProfiles();

// Glob match (fnmatch semantics, no path handling). Exact names match too.
bool matches(const std::string &pattern, const std::string &name);

// Pattern syntax check: 1..64 chars from [A-Za-z0-9_.:@*?!\[\]-].
bool validPattern(const std::string &pattern);

// `loopback` keeps Qt's behaviour of always listing loopback addresses in
// allowlist mode; in denylist mode loopback is hidden only if an exclude
// pattern explicitly matches it.
Verdict decide(const Config &cfg, const std::string &interfaceName, bool loopback = false);

const char *modeName(Mode m);

} // namespace ilnf
