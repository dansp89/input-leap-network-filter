# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub:
**Security → Report a vulnerability** on
https://github.com/dansp89/input-leap-network-filter. Do not open a public
issue for security problems. You should get an answer within 7 days.

## Supported versions

Only the latest release receives fixes.

## Security design

- Runs as the regular user. Refuses to run as root. `sudo` is used only to
  install build dependencies, and only after explicit consent.
- `LD_PRELOAD` is set only for the Input Leap GUI process, by a wrapper.
  `/etc/ld.so.preload` and global environment changes are never used.
- The wrapper preloads the library only if it is a regular file owned by the
  user and not writable by group or others; otherwise Input Leap starts
  without the filter.
- The library removes itself from `LD_PRELOAD` when loaded, so child
  processes do not inherit it.
- Configuration, manifest and locale files are parsed as data and never
  sourced or evaluated. Interface patterns are restricted to
  `[A-Za-z0-9_.:@*?!\[\]-]`, max 64 characters.
- Writes are atomic (temporary file + rename), refuse to follow symbolic
  links, and files whose ownership by this project cannot be proven are not
  overwritten.
- No telemetry and no network access, except `update`, which runs only when
  asked, downloads over HTTPS from GitHub Releases, verifies SHA-256 and
  rejects archives containing absolute or `..` paths.
- Flatpak, Snap and AppImage installations are refused instead of bypassing
  their isolation.
