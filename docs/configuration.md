# Configuration

File: `~/.config/input-leap-network-filter/config.toml` (or
`$XDG_CONFIG_HOME/...`, or the path in `ILNF_CONFIG`). It is created with the
defaults on install. Changes apply the next time Input Leap starts.

The file uses a small subset of TOML: `[section]`, `key = value`, booleans,
strings in double quotes, arrays of strings (may span several lines),
`#` comments. It is parsed as data and never executed.

```toml
[filter]
enabled = true          # false: behave exactly like Input Leap without the filter
mode = "denylist"       # "denylist" | "allowlist" | "off"

[interfaces]
profiles = ["docker", "lxc"]
exclude = []            # extra names/patterns to hide
include = []            # names/patterns always shown (win over everything)

[logging]
enabled = false         # messages go to the Input Leap process stderr
level = "warn"          # error | warn | info | debug
```

## Rules

- **include** always wins.
- In **denylist** mode, an interface is hidden if it matches a pattern of an
  enabled profile or of `exclude`.
- In **allowlist** mode, only interfaces matching `include` are shown;
  loopback is kept, as Qt does.
- Patterns are exact names or globs (`*`, `?`, `[a-z]`, `[!0-9]`), 1–64
  characters from `A-Z a-z 0-9 _ . : @ - * ? ! [ ]`.
- Loopback is never hidden unless you exclude it explicitly (`exclude = ["lo"]`).
- **If the file is invalid, nothing is filtered** and an error is printed on
  the Input Leap stderr. `input-leap-network-filter doctor` reports it.
- Interfaces are never hidden just because their address is in
  10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16. VPN, WireGuard, Tailscale,
  ZeroTier, VLANs, tunnels and custom bridges are kept unless you add them.

## Profiles

| Profile | Patterns |
| --- | --- |
| `docker` | `docker*` `br-*` `veth*` |
| `lxc` | `lxcbr*` |
| `lxd` | `lxdbr*` |
| `incus` | `incusbr*` |
| `podman` | `podman*` `cni-podman*` |
| `kubernetes` | `cni*` `flannel*` `cali*` `kube-ipvs*` |
| `libvirt` | `virbr*` `vnet*` |
| `openvswitch` | `ovs-*` |

The defaults (`docker`, `lxc`) reproduce the original manual fix this project
grew out of. Patterns are candidates, not proof that an interface is virtual:
check with `input-leap-network-filter preview`.

## From the command line

```bash
input-leap-network-filter configure --add-exclude 'virbr*'
input-leap-network-filter configure --add-include br-lan
input-leap-network-filter configure --profiles docker,lxc,libvirt
input-leap-network-filter configure --mode allowlist --add-include 'wl*'
input-leap-network-filter configure --show
input-leap-network-filter configure --edit     # $EDITOR, validated afterwards
input-leap-network-filter reset                # defaults (old file backed up)
```

Every change is validated with the same parser the library uses before the
file is replaced.

## Environment variables

| Variable | Effect |
| --- | --- |
| `ILNF_DISABLE=1` | start Input Leap without filtering (wrapper and library) |
| `ILNF_CONFIG=/path` | use another config file |
| `ILNF_DEBUG=1` | library prints what it hides on stderr |
| `ILNF_LANG=pt_BR` | CLI language (`en`, `pt_BR`, `es`) |
| `NO_COLOR=1` | no colours in the CLI |
