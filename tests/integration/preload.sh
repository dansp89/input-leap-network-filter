#!/usr/bin/env bash
# End-to-end check of the preloaded library against a real Qt process.
# Uses loopback as the filtered interface so no network is modified.
set -euo pipefail
lib=$1 fake=$2
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

base=$(ILNF_CONFIG=/nonexistent "$fake")
grep -q '^ADDR 127.0.0.1$' <<<"$base" || fail "baseline lacks 127.0.0.1"

printf '[interfaces]\nprofiles = []\nexclude = ["lo"]\n' >"$tmp/c.toml"
out=$(ILNF_CONFIG="$tmp/c.toml" LD_PRELOAD="$lib" "$fake" a "b c" --exit 7) && rc=0 || rc=$?
[ "$rc" = 7 ] || fail "exit code not preserved ($rc)"
grep -q '^ADDR 127.0.0.1$' <<<"$out" && fail "loopback not filtered"
grep -q '^ADDR ::1$' <<<"$out" && fail "IPv6 loopback not filtered"
grep -qx 'ARG b c' <<<"$out" || fail "argument with space not preserved"
grep -qx 'PRELOAD ' <<<"$out" || fail "library did not strip itself from LD_PRELOAD"
# Kept addresses are identical to the baseline minus loopback.
diff <(grep '^ADDR' <<<"$base" | grep -v -e ' 127.0.0.1$' -e ' ::1$') <(grep '^ADDR' <<<"$out") \
  || fail "non-filtered addresses changed"

# Other LD_PRELOAD entries are preserved for the process environment.
out=$(ILNF_CONFIG="$tmp/c.toml" LD_PRELOAD="$lib:/nonexistent-other.so" "$fake" 2>/dev/null)
grep -qx 'PRELOAD /nonexistent-other.so' <<<"$out" || fail "foreign LD_PRELOAD entry lost"

# Invalid config => original behaviour.
printf '[filter]\nenabled = maybe\n' >"$tmp/bad.toml"
out=$(ILNF_CONFIG="$tmp/bad.toml" LD_PRELOAD="$lib" "$fake" 2>/dev/null)
grep -q '^ADDR 127.0.0.1$' <<<"$out" || fail "invalid config should pass through"

# Disabled.
printf '[filter]\nenabled = false\n[interfaces]\nexclude = ["lo"]\n' >"$tmp/off.toml"
out=$(ILNF_CONFIG="$tmp/off.toml" LD_PRELOAD="$lib" "$fake")
grep -q '^ADDR 127.0.0.1$' <<<"$out" || fail "disabled config should pass through"

echo "preload integration: OK"
