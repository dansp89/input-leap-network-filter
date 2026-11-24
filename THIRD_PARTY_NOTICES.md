# Third-party notices

This repository contains only original code, released under the MIT License
(see `LICENSE`). It does not include, copy or modify source code from the
projects below; it builds against them on the user's machine.

## Qt (Qt Core, Qt Network)

- Used as: dynamically linked system library and public C++ API headers.
- License: GNU LGPL v3 (or GPL v2/v3, or commercial), see https://www.qt.io/licensing/
- `src/filter.cpp` provides its own implementation of the public function
  `QNetworkInterface::allAddresses()` and calls the original Qt implementation
  through `dlsym(RTLD_NEXT, ...)`. Qt itself is not modified, redistributed or
  statically linked. Users can replace Qt freely, as the LGPL requires.

## Input Leap

- Used as: the program whose process the library is loaded into at runtime.
- License: GNU GPL v2, see https://github.com/input-leap/input-leap
- No Input Leap code is included, linked or redistributed. The executable is
  never modified; it is only renamed (local installs) or left untouched
  (system installs) and started with `LD_PRELOAD`.

Input Leap Network Filter is an independent project and is not affiliated
with, endorsed by or maintained by the Input Leap or Qt projects.
