#!/usr/bin/env bash
# End-to-end tests of the CLI in throw-away HOME directories.
# Never touches the real network, the real HOME or system files.
#   tests/integration/cli.sh PATH/TO/fake-input-leap
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
FAKE=${1:?usage: cli.sh fake-input-leap}
CLI="$ROOT/bin/input-leap-network-filter"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
pass=0 failn=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { failn=$((failn + 1)); printf '  FAIL %s\n' "$1"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else ko "$d"; fi; }

# new_home NAME -> sets H and environment for an isolated user
new_home() {
  H="$WORK/$1"
  mkdir -p "$H/.local/bin"
  export HOME=$H XDG_CONFIG_HOME="" XDG_DATA_HOME="" XDG_STATE_HOME="" LANG=C ILNF_LANG=en NO_COLOR=1
  export PATH="$H/.local/bin:/usr/bin:/bin"
  unset LD_PRELOAD
}
ilnf() { "$CLI" --non-interactive "$@"; }
addr_count() { "$H/.local/bin/input-leap" | grep -c '^ADDR'; }
baseline=$("$FAKE" | grep -c '^ADDR')
# Tests hide loopback so they work on machines without containers.
hide_lo() { mkdir -p "$H/.config/input-leap-network-filter"; printf '[interfaces]\nprofiles = []\nexclude = ["lo"]\n' >"$H/.config/input-leap-network-filter/config.toml"; }

echo "# fresh install (inplace)"
new_home fresh
cp "$FAKE" "$H/.local/bin/input-leap"
orig_sha=$(sha256sum "$FAKE" | cut -d' ' -f1)
hide_lo
check "install succeeds" ilnf install -q
check "original preserved" test "$(sha256sum "$H/.local/bin/input-leap.original" | cut -d' ' -f1)" = "$orig_sha"
check "wrapper installed" grep -q 'managed wrapper' "$H/.local/bin/input-leap"
check "loopback hidden through wrapper" test "$(addr_count)" -lt "$baseline"
# shellcheck disable=SC2016  # literal $(x) must reach the program unexpanded
out=$("$H/.local/bin/input-leap" "a b" '$(x)' --exit 9); rc=$?
check "exit code preserved" test $rc = 9
check "arguments preserved" grep -qxF 'ARG a b' <<<"$out"
# shellcheck disable=SC2016
check "special arguments preserved" grep -qxF 'ARG $(x)' <<<"$out"
check "filter not propagated to children" grep -qx 'PRELOAD ' <<<"$out"
out=$(LD_PRELOAD=/nonexistent.so "$H/.local/bin/input-leap" 2>/dev/null)
check "foreign LD_PRELOAD kept" grep -qx 'PRELOAD /nonexistent.so' <<<"$out"
check "CLI linked" test -L "$H/.local/bin/input-leap-network-filter"

echo "# idempotency"
touch "$WORK/mark"; sleep 1
ilnf install -q && ilnf install -q
changed=$(find "$H" -type f -newer "$WORK/mark" ! -name lock | wc -l)
check "reinstall changes no file" test "$changed" = 0
check "no wrapper over wrapper" bash -c "! grep -q 'managed wrapper' '$H/.local/bin/input-leap.original'"
check "single backup/original" test "$(find "$H/.local/bin" -name '*original*' | wc -l)" = 1

echo "# status / doctor / json"
check "status ok" ilnf status -q
check "doctor healthy" ilnf doctor -q
check "doctor --json valid" bash -c "'$CLI' doctor --json | python3 -m json.tool >/dev/null"
check "status --json valid" bash -c "'$CLI' status --json | python3 -m json.tool >/dev/null"
check "interfaces --json valid" bash -c "'$CLI' interfaces --json | python3 -m json.tool >/dev/null"
check "version --json valid" bash -c "'$CLI' version --json | python3 -m json.tool >/dev/null"

echo "# enable / disable"
ilnf disable -q
check "disabled => original behaviour" test "$(addr_count)" = "$baseline"
ilnf enable -q
check "enabled => filtered" test "$(addr_count)" -lt "$baseline"
n=$(ILNF_DISABLE=1 addr_count)
check "ILNF_DISABLE env bypass" test "$n" = "$baseline"

echo "# configuration"
check "invalid pattern rejected" bash -c "! '$CLI' --non-interactive configure --add-exclude 'a;rm' 2>/dev/null"
ilnf configure --add-include lo -q >/dev/null
check "include wins over exclude" test "$(addr_count)" = "$baseline"
ilnf configure --remove-include lo >/dev/null
printf '[filter]\nenabled = perhaps\n' >"$H/.config/input-leap-network-filter/config.toml"
check "invalid config => pass-through" test "$("$H/.local/bin/input-leap" 2>/dev/null | grep -c '^ADDR')" = "$baseline"
check "doctor reports invalid config" bash -c "! '$CLI' --non-interactive doctor -q"
hide_lo

echo "# safety of the library file"
chmod 666 "$H/.local/lib/input-leap-network-filter/network-filter.so"
check "world-writable library is not preloaded" test "$(addr_count)" = "$baseline"
chmod 644 "$H/.local/lib/input-leap-network-filter/network-filter.so"
mv "$H/.local/lib/input-leap-network-filter/network-filter.so" "$WORK/lib.bak"
check "missing library => Input Leap still starts" test "$(addr_count)" = "$baseline"
check "doctor detects missing library" bash -c "! '$CLI' --non-interactive doctor -q"
check "repair restores library" ilnf repair -q
check "filter works after repair" test "$(addr_count)" -lt "$baseline"

echo "# external update of Input Leap"
cp "$FAKE" "$H/.local/bin/input-leap.new"; printf 'x' >>"$H/.local/bin/input-leap.new"
mv -f "$H/.local/bin/input-leap.new" "$H/.local/bin/input-leap" # user overwrote the wrapper
check "doctor detects overwrite" bash -c "! '$CLI' --non-interactive doctor -q"
check "repair refuses without consent" bash -c "! '$CLI' --non-interactive repair -q 2>/dev/null"
check "repair --yes adopts update" ilnf repair -q --yes
check "wrapper back" grep -q 'managed wrapper' "$H/.local/bin/input-leap"
check "filtered after adopting update" test "$(addr_count)" -lt "$baseline"

echo "# concurrency"
exec 8>"$H/.local/state/input-leap-network-filter/lock"; flock -n 8
ilnf install -q 2>/dev/null; rc=$?
check "concurrent run is refused (exit 8)" test $rc = 8
exec 8>&-

echo "# uninstall"
check "uninstall" ilnf uninstall -q
check "binary restored in place" bash -c "head -c4 '$H/.local/bin/input-leap' | grep -q ELF"
check "no .original left" test ! -e "$H/.local/bin/input-leap.original"
check "library removed" test ! -e "$H/.local/lib/input-leap-network-filter"
check "config preserved" test -f "$H/.config/input-leap-network-filter/config.toml"
check "uninstall again => not installed (3)" bash -c "'$CLI' --non-interactive uninstall -q 2>/dev/null; test \$? = 3"
check "purge" ilnf uninstall --purge -q
check "config removed by purge" test ! -e "$H/.config/input-leap-network-filter"

echo "# legacy migration"
new_home legacy
mkdir -p "$H/.local/lib/input-leap"
cp "$FAKE" "$H/.local/bin/input-leap.original"
cat >"$H/.local/bin/input-leap" <<'L'
#!/bin/bash
export LD_PRELOAD="$HOME/.local/lib/input-leap/network-filter.so${LD_PRELOAD:+:$LD_PRELOAD}"
exec "$HOME/.local/bin/input-leap.original" "$@"
L
chmod +x "$H/.local/bin/input-leap"
hide_lo
check "legacy install migrates" ilnf install -q
check "legacy wrapper backed up" test -f "$H/.local/share/input-leap-network-filter/backups/legacy-wrapper"
check "new wrapper in place" grep -q 'managed wrapper' "$H/.local/bin/input-leap"
check "filtered after migration" test "$(addr_count)" -lt "$baseline"

echo "# conflict: unknown .original"
new_home conflict
cp "$FAKE" "$H/.local/bin/input-leap"; cp "$FAKE" "$H/.local/bin/input-leap.original"
ilnf install -q 2>/dev/null; rc=$?
check "refuses to overwrite unproven file (6)" test $rc = 6
check "nothing changed" test ! -e "$H/.local/state/input-leap-network-filter/manifest"

echo "# external mode (binary not owned by the user / package managed)"
new_home external
mkdir -p "$WORK/sysbin" "$WORK/apps"
cp "$FAKE" "$WORK/sysbin/input-leap"; chmod 555 "$WORK/sysbin"
mkdir -p "$H/.local/share/applications"
printf '[Desktop Entry]\nName=Input Leap\nExec=%s %%U\nType=Application\n' "$WORK/sysbin/input-leap" >"$H/.local/share/applications/input-leap.desktop"
hide_lo
check "external install" ilnf install -q --path "$WORK/sysbin/input-leap"
check "system binary untouched" test ! -e "$WORK/sysbin/input-leap.original"
check "external wrapper filters" test "$("$H/.local/lib/input-leap-network-filter/input-leap" | grep -c '^ADDR')" -lt "$baseline"
check "PATH shim created" grep -q 'managed wrapper' "$H/.local/bin/input-leap"
check "desktop entry points to wrapper" grep -q "^Exec=$H/.local/lib/input-leap-network-filter/input-leap %U" "$H/.local/share/applications/input-leap.desktop"
check "uninstall external" ilnf uninstall -q
check "desktop entry restored" grep -q "^Exec=$WORK/sysbin/input-leap %U" "$H/.local/share/applications/input-leap.desktop"
check "shim removed" test ! -e "$H/.local/bin/input-leap"
chmod 755 "$WORK/sysbin"

echo "# missing executable"
new_home missing
ilnf install -q --path "$H/nope" 2>/dev/null; rc=$?
check "missing Input Leap => exit 3" test $rc = 3

echo "# non-Qt executable is unsupported"
new_home noqt
cp /bin/true "$H/.local/bin/input-leap"
ilnf install -q 2>/dev/null; rc=$?
check "non-Qt binary => exit 4, unchanged" test $rc = 4 -a ! -e "$H/.local/bin/input-leap.original"

echo
echo "passed: $pass  failed: $failn"
[[ $failn == 0 ]]
