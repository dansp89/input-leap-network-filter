# Ubuntu 22.04 LTS guide

This is the environment where the project was developed and tested:
Ubuntu 22.04.5, x86_64, Qt 6.2.4, Input Leap 3.0.3 (`aac3e88`) built from
source and installed in `~/.local/bin`, Docker and LXC with many bridges.

## 1. Install

```bash
git clone https://github.com/dansp89/input-leap-network-filter.git
cd input-leap-network-filter
bash install.sh
```

If the build tools are missing, the installer lists the packages and asks
before running `sudo apt-get install`:

- Input Leap built with Qt 6: `g++ cmake pkg-config qt6-base-dev`
- Input Leap built with Qt 5: `g++ cmake pkg-config qtbase5-dev`

Ubuntu 22.04 does not ship `.pc` files for Qt 6, so `pkg-config` cannot find
it. The installer uses CMake (`Qt6Config.cmake` is shipped) and falls back to
locating the headers in `/usr/include/<multiarch>/qt6` directly.

## 2. Check

```bash
input-leap-network-filter preview   # what Input Leap will list
input-leap-network-filter doctor
```

Restart Input Leap (close it from the tray icon too). The "IP addresses" line
should show only your real network addresses.

## 3. If you had applied the manual fix

If `~/.local/bin/input-leap` is the hand-written wrapper that exported
`LD_PRELOAD=~/.local/lib/input-leap/network-filter.so` and ran
`input-leap.original`, the installer recognises it, saves it in
`~/.local/share/input-leap-network-filter/backups/legacy-wrapper` and replaces
it with the managed wrapper. `~/.local/lib/input-leap/` is no longer used and
can be deleted.

## 4. When Input Leap is updated

If you install a new Input Leap build by copying it over
`~/.local/bin/input-leap`, the wrapper is overwritten and the filter stops.
Run:

```bash
input-leap-network-filter doctor   # reports "replaced externally"
input-leap-network-filter repair   # adopts the new binary, restores the wrapper
```

## 5. Remove

```bash
input-leap-network-filter uninstall          # restores ~/.local/bin/input-leap
input-leap-network-filter uninstall --purge  # also config, state and backups
```
