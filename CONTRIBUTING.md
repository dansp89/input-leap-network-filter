# Contributing

Thanks for helping! Issues and pull requests are welcome in English or
Portuguese.

## Development setup

Requirements: a C++17 compiler, CMake ≥ 3.16, Qt 5 and/or Qt 6 development
files (`qt6-base-dev` / `qtbase5-dev` on Debian/Ubuntu), Bash ≥ 4.4.

```bash
make build        # Qt6 build in build/ (QT=5 for Qt5)
make test         # unit + library integration + CLI end-to-end tests
make lint         # shellcheck (needs shellcheck installed)
make bench        # filter micro-benchmark
```

The tests never touch the real network or your real `$HOME`: they create
temporary home directories and use loopback as the interface to hide.

## Guidelines

- Keep it small: Bash for the CLI, C++17 for the library, no new runtime
  dependencies for end users.
- The filtering rules live in `src/config.cpp` and are shared by the library,
  the `ilnf-probe` helper and the tests. Change them in one place.
- Every state-changing operation must stay idempotent and reversible. Add a
  case to `tests/integration/cli.sh` for new behaviour.
- New user-facing strings go to `locales/en/messages.txt` (and ideally
  `pt_BR` and `es`).
- Do not mark a distribution as *Tested* unless you ran the full test suite
  and a real Input Leap session on it; please report results in an issue.

## Reporting a compatibility result

Run `input-leap-network-filter doctor --json` and paste the output together
with your distribution, Input Leap version and how it was installed.
