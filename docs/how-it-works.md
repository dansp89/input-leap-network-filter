# How it works

## The problem

The Input Leap GUI (server mode) shows "IP addresses:" in its main window. It
gets them from Qt's `QNetworkInterface::allAddresses()`, which returns the
addresses of **every** interface that is up. On a machine with Docker, LXC,
libvirt, Kubernetes and similar tools that can be dozens of bridge addresses,
and the window grows sideways until it is wider than the screen.

A quick static check confirms that the GUI imports the function:

```bash
nm -D -C "$(command -v input-leap)" | grep QNetworkInterface
#   U QNetworkInterface::allAddresses()@Qt_6
```

## The fix

`network-filter.so` defines its own `QNetworkInterface::allAddresses()`.
Because it is loaded with `LD_PRELOAD`, the dynamic linker resolves the GUI's
reference to it instead of to `libQt6Network.so` (or `libQt5Network.so`).

The replacement:

1. Calls the **original** Qt function, found with `dlsym(RTLD_NEXT, ...)`, so
   Qt's own semantics stay intact (interfaces that are down skipped, IPv4 and
   IPv6, order, scope IDs, duplicates).
2. Reads the configuration and asks Qt for the interface list.
3. Removes from the original result only the addresses that belong
   **exclusively** to filtered interfaces. If the same address is also on an
   interface that is kept, it stays.
4. Behaves exactly like the original whenever something is off: invalid
   configuration, filter disabled, `ILNF_DISABLE` set, Qt major mismatch.

Nothing else changes: interfaces, routes, firewall, DNS, containers and the
networking of every other program are untouched, because the filter lives only
inside the Input Leap GUI process.

### Not leaking into child processes

The GUI starts `input-leaps`/`input-leapc` as child processes, and
`LD_PRELOAD` is inherited by default. The library removes its own path from
`LD_PRELOAD` in a constructor as soon as it is loaded, keeping any other
entries. The children therefore run without the filter.

A consequence: the library must be preloaded **directly** into the GUI. If a
helper program such as `setsid` or `timeout` sits between the variable and the
GUI, the helper loads the library first and the GUI does not get it. Use
`env` as the last hop (`setsid env LD_PRELOAD=... input-leap`). The wrapper
created by the installer uses `exec`, so it is not affected.

### ABI

`allAddresses()` is a static member function without arguments returning
`QList<QHostAddress>`. Its mangled name is the same in Qt 5 and Qt 6, but the
`QList` layout is not, so the library is built against the **same Qt major**
that the Input Leap executable uses (detected with `readelf -d`). Within one
major version Qt keeps binary compatibility, so a library built with Qt 6.2
headers works with later Qt 6 releases. The installer validates every build
before activating it: it checks the exported symbol and the Qt libraries it
links to, then loads it into a small Qt test program and checks that a filter
actually takes effect.

## Install modes

| Mode | When | What is changed |
| --- | --- | --- |
| `inplace` | Input Leap is a user-owned binary not managed by a package manager (e.g. `~/.local/bin/input-leap`) | The binary is renamed to `input-leap.original` (atomic rename, same directory) and a small wrapper takes its place. Menu entries, autostart and terminal all keep working because the path does not change. |
| `external` | Binary owned by root or by a package (`/usr/bin`, `/opt`, ...) | The binary is never touched. A wrapper is created in `~/.local/lib/input-leap-network-filter/input-leap`, a shim in `~/.local/bin/input-leap` (only if the name is free) and user-level copies of the desktop/autostart entries that point to the wrapper. |

Flatpak, Snap and AppImage are refused: they either isolate the process or
bundle their own Qt.

## Files

| Path | Content |
| --- | --- |
| `~/.config/input-leap-network-filter/config.toml` | configuration |
| `~/.local/lib/input-leap-network-filter/` | `network-filter.so`, previous version `.prev`, `ilnf-probe`, test program, external wrapper |
| `~/.local/share/input-leap-network-filter/app/` | installed copy of the CLI |
| `~/.local/share/input-leap-network-filter/backups/` | replaced desktop entries, migrated legacy wrapper, old configs |
| `~/.local/state/input-leap-network-filter/` | `manifest` (SHA-256 of every managed file), `disabled` flag, lock, journal |
| `~/.local/bin/input-leap-network-filter` | symlink to the CLI |

## Robustness

- **Idempotent**: re-running `install` with nothing to do changes no file
  (checked by the test suite).
- **Lock** (`flock`) prevents concurrent runs (exit code 8).
- **Journal** records in-progress operations; an interrupted run is reported
  and completed by the next `install`/`repair`.
- **Ownership**: a file is only replaced if the manifest or a marker proves it
  belongs to this project. An unknown `input-leap.original` stops the install
  with exit code 6.
- **External updates**: if Input Leap is replaced by a new binary over the
  wrapper, `doctor` reports it and `repair` (with confirmation) adopts the new
  binary and restores the wrapper.

## Performance

The filter runs only when the GUI asks for the address list (at start-up and
when it refreshes the window). There is no daemon, no polling and no network
access. `make bench` measures the rule evaluation only, on synthetic interface
names (it does not create interfaces). Result on the maintainer's machine
(Intel laptop, Ubuntu 22.04, Release build):

| interfaces | time per evaluation of all interfaces | per interface |
| ---: | ---: | ---: |
| 10 | 6.8 µs | 684 ns |
| 50 | 26.9 µs | 537 ns |
| 100 | 41.9 µs | 419 ns |
| 500 | 229.3 µs | 459 ns |
| 1000 | 470.9 µs | 471 ns |

This does not include Qt's own interface enumeration, which the original
function does anyway. The filter additionally calls `allInterfaces()` once and
reads the small config file once per call.
