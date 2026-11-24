# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-23

First public, experimental release.

### Added
- `LD_PRELOAD` library that interposes `QNetworkInterface::allAddresses()`,
  calls the original Qt function and removes only addresses that belong
  exclusively to filtered interfaces (Qt5 and Qt6).
- Library removes itself from `LD_PRELOAD` on load, so `input-leaps` and
  `input-leapc` do not inherit it.
- Configuration file (TOML subset) with profiles, exclude/include patterns,
  denylist/allowlist/off modes; invalid configuration means no filtering.
- `input-leap-network-filter` CLI: install, uninstall (`--purge`), update,
  enable, disable, status, doctor, repair, rollback, interfaces, preview,
  configure, reset, version, help; `--json`, `--dry-run`, `--path` and other
  global options; interactive menu; English, Brazilian Portuguese and Spanish.
- Idempotent installer with SHA-256 manifest, lock, journal, atomic writes,
  library validation (symbol check + smoke test) before activation, migration
  of the manual wrapper used before this project, external-update detection.
- Two install modes: in-place wrapper for user-owned binaries, external
  wrapper + desktop overrides for system/package binaries.
- Unit tests (C++), library integration test, CLI end-to-end test suite and a
  micro-benchmark.
