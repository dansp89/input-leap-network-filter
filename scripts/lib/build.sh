# shellcheck shell=bash
# Build the filter library and probe, with fallbacks:
#   1. CMake  2. pkg-config + compiler  3. header discovery + compiler
# SPDX-License-Identifier: MIT

# Packages providing a compiler, CMake and Qt development files.
deps_for() {
  local qt=$1
  case "$PKG_MGR:$qt" in
    apt-get:6) echo "g++ cmake pkg-config qt6-base-dev" ;;
    apt-get:5) echo "g++ cmake pkg-config qtbase5-dev" ;;
    dnf:6 | yum:6) echo "gcc-c++ cmake pkgconf-pkg-config qt6-qtbase-devel" ;;
    dnf:5 | yum:5) echo "gcc-c++ cmake pkgconf-pkg-config qt5-qtbase-devel" ;;
    pacman:6) echo "gcc cmake pkgconf qt6-base" ;;
    pacman:5) echo "gcc cmake pkgconf qt5-base" ;;
    zypper:6) echo "gcc-c++ cmake pkg-config qt6-base-devel" ;;
    zypper:5) echo "gcc-c++ cmake pkg-config libqt5-qtbase-devel" ;;
  esac
}

# Locate Qt include dir for the given major (QtNetwork headers).
find_qt_include() {
  local qt=$1 d
  for d in /usr/include/*-linux-gnu*/qt"$qt" /usr/include/qt"$qt" /usr/include/qt /usr/lib*/qt"$qt"/include; do
    [[ -f $d/QtNetwork/QNetworkInterface || -f $d/QtNetwork/qnetworkinterface.h ]] && {
      echo "$d"
      return 0
    }
  done
  return 1
}

find_qt_libdir() {
  local qt=$1 f
  for f in /usr/lib/*-linux-gnu/libQt"$qt"Network.so /usr/lib64/libQt"$qt"Network.so /usr/lib/libQt"$qt"Network.so; do
    [[ -e $f ]] && {
      dirname -- "$f"
      return 0
    }
  done
  return 1
}

qt_dev_available() {
  local qt=$1
  find_qt_include "$qt" >/dev/null && find_qt_libdir "$qt" >/dev/null
}

# Install missing build dependencies, only with explicit consent.
ensure_build_deps() {
  local qt=$1 pkgs
  detect_toolchain
  if [[ -n $CXX_BIN ]] && qt_dev_available "$qt"; then
    verbose "$(t deps_ok)"
    return 0
  fi
  pkgs=$(deps_for "$qt")
  [[ -n $pkgs ]] || die "$EX_DEPS" "$(t err_deps_unknown "$qt")"
  warn "$(t deps_missing "$pkgs")"
  has_sudo || die "$EX_DEPS" "$(t err_no_sudo "$pkgs")"
  confirm "$(t ask_install_deps "$pkgs")" || die "$EX_DEPS" "$(t err_deps_declined "$pkgs")"
  # shellcheck disable=SC2086  # word splitting of the package list is intended
  case $PKG_MGR in
    apt-get) run sudo apt-get install -y --no-install-recommends $pkgs ;;
    dnf) run sudo dnf install -y $pkgs ;;
    yum) run sudo yum install -y $pkgs ;;
    pacman) run sudo pacman -S --needed --noconfirm $pkgs ;;
    zypper) run sudo zypper --non-interactive install $pkgs ;;
  esac || die "$EX_DEPS" "$(t err_deps_failed)"
  detect_toolchain
}

# build_all QT OUTDIR -> OUTDIR/network-filter.so, ilnf-probe, fake-input-leap
build_all() {
  local qt=$1 out=$2 src=$ILNF_ROOT bdir
  mkdir -p -- "$out"
  bdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf -- '$bdir'" RETURN

  if [[ -n $CMAKE_BIN ]]; then
    verbose "$(t build_cmake)"
    if "$CMAKE_BIN" -S "$src" -B "$bdir" -DILNF_QT_MAJOR="$qt" -DILNF_BUILD_TESTS=OFF \
      -DCMAKE_BUILD_TYPE=Release >"$bdir/.log" 2>&1 &&
      "$CMAKE_BIN" --build "$bdir" -j"$(nproc 2>/dev/null || echo 2)" >>"$bdir/.log" 2>&1; then
      cp -- "$bdir/network-filter-qt$qt.so" "$out/network-filter.so"
      cp -- "$bdir/ilnf-probe" "$bdir/fake-input-leap" "$out/"
      return 0
    fi
    debug "$(cat "$bdir/.log")"
    warn "$(t build_cmake_failed)"
  fi

  [[ -n $CXX_BIN ]] || die "$EX_BUILD" "$(t err_no_compiler)"
  local -a cflags=() libs=()
  if [[ -n $PKGCONFIG_BIN ]] && "$PKGCONFIG_BIN" --exists "Qt${qt}Network" 2>/dev/null; then
    verbose "$(t build_pkgconfig)"
    read -r -a cflags < <("$PKGCONFIG_BIN" --cflags "Qt${qt}Core" "Qt${qt}Network")
    read -r -a libs < <("$PKGCONFIG_BIN" --libs "Qt${qt}Core" "Qt${qt}Network")
  else
    # Ubuntu 22.04 ships Qt6 without .pc files: discover headers instead.
    verbose "$(t build_discovery)"
    local inc libdir
    inc=$(find_qt_include "$qt") || die "$EX_DEPS" "$(t err_no_qt_headers "$qt")"
    libdir=$(find_qt_libdir "$qt") || die "$EX_DEPS" "$(t err_no_qt_headers "$qt")"
    cflags=(-I"$inc" -I"$inc/QtCore" -I"$inc/QtNetwork")
    libs=(-L"$libdir" -lQt"$qt"Network -lQt"$qt"Core)
  fi
  local -a common=(-std=c++17 -O2 -Wall -I"$src/include")
  "$CXX_BIN" "${common[@]}" -fPIC -shared "${cflags[@]}" "$src/src/filter.cpp" "$src/src/config.cpp" \
    -o "$out/network-filter.so" "${libs[@]}" -ldl -Wl,-z,now -Wl,-z,relro >"$bdir/.log" 2>&1 &&
    "$CXX_BIN" "${common[@]}" "$src/tools/probe.cpp" "$src/src/config.cpp" "$src/src/interfaces.cpp" \
      -o "$out/ilnf-probe" >>"$bdir/.log" 2>&1 &&
    "$CXX_BIN" "${common[@]}" -fPIC "${cflags[@]}" "$src/tests/fixtures/fake_input_leap.cpp" \
      -o "$out/fake-input-leap" "${libs[@]}" >>"$bdir/.log" 2>&1 || {
    cat "$bdir/.log" >&2
    die "$EX_BUILD" "$(t err_build_failed)"
  }
}

# Build only the Qt-free probe (used by `interfaces`/`preview` before install).
build_probe_only() {
  local out=$1
  detect_toolchain
  [[ -n $CXX_BIN ]] || return 1
  mkdir -p -- "$(dirname -- "$out")"
  "$CXX_BIN" -std=c++17 -O2 -I"$ILNF_ROOT/include" "$ILNF_ROOT/tools/probe.cpp" \
    "$ILNF_ROOT/src/config.cpp" "$ILNF_ROOT/src/interfaces.cpp" -o "$out" 2>/dev/null
}

# Validate a freshly built library before activating it.
# validate_library LIB FAKE QT
validate_library() {
  local lib=$1 fake=$2 qt=$3 dyn out cfg
  dyn=$(LC_ALL=C readelf -d -- "$lib" 2>/dev/null) || return 1
  grep -q "libQt${qt}Network" <<<"$dyn" || {
    error "$(t val_wrong_qt "$qt")"
    return 1
  }
  if [[ $qt == 6 ]] && grep -q libQt5 <<<"$dyn"; then return 1; fi
  if [[ $qt == 5 ]] && grep -q libQt6 <<<"$dyn"; then return 1; fi
  local syms
  syms=$(LC_ALL=C readelf --dyn-syms -W -- "$lib" 2>/dev/null || true)
  grep -qE " GLOBAL +DEFAULT +[0-9]+ $FILTER_SYMBOL" <<<"$syms" || {
    error "$(t val_no_symbol)"
    return 1
  }
  # Smoke test: load the library into a real Qt process. The test program
  # hides loopback through an isolated config and must still exit cleanly.
  cfg=$(mktemp)
  printf '[interfaces]\nprofiles = []\nexclude = ["lo"]\n' >"$cfg"
  # `env` sets LD_PRELOAD only for the Qt process (the library strips itself
  # from LD_PRELOAD in the first process that loads it).
  out=$(timeout 20 env ILNF_CONFIG="$cfg" LD_PRELOAD="$lib" "$fake" --exit 0 2>&1) || {
    rm -f -- "$cfg"
    error "$(t val_smoke_failed)"
    debug "$out"
    return 1
  }
  rm -f -- "$cfg"
  if grep -qx 'ADDR 127.0.0.1' <<<"$out"; then
    error "$(t val_not_effective)"
    return 1
  fi
  return 0
}
