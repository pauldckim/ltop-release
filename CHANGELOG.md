# Changelog

All notable public changes to ltop releases are recorded here.

## 0.1.0 — 2026-09-05

First public release. Single-binary, keyboard-only TUI that monitors a local
llama.cpp `llama-server` and the OS process behind it, read-only.

### What it does

- Polls the server's `/metrics` (Prometheus), `/slots` and `/props`
  endpoints plus local process CPU/memory and renders an integrated
  dashboard (CPU, Memory, Inference, Slots, Server panels). No daemon,
  Prometheus, or Grafana required.
- Per-source status (`fresh` / `stale` / `unavailable` / `disabled`) with
  last-success time; a failing source never masquerades as fresh and never
  takes down the rest of the dashboard.
- Live generation estimate: while a slot is processing, the Inference panel
  shows in-flight tokens and a live tok/s derived from `/slots` (the
  server's generated-token counters only move when a slot is released, so a
  `/metrics`-only view would show a frozen total and `0.0 tok/s` mid-stream).
- CLI: `--endpoint` (or positional), `--interval` (0.5–10.0 s), `--pid`,
  `--theme` (tokyo-night | catppuccin-mocha | dracula | nord), `--help`,
  `--version`.
- Keyboard: `q`/`Ctrl-C` quit, `r` refresh, `+`/`-` interval,
  `Tab`/`Shift+Tab` panel focus, `t`/`T` theme.

### Platforms

| Platform | Artifact | Notes |
|---|---|---|
| macOS x86_64 | `ltop-v0.1.0-macos-x86_64.zip` | unsigned (no Developer ID / notarization yet) |
| Windows x86_64 | `ltop-v0.1.0-windows-x86_64.zip` | unsigned (no Authenticode yet) |
| Linux x86_64 | `ltop-v0.1.0-linux-x86_64.tar.gz` | glibc dynamic build |

macOS arm64, Linux aarch64 and Windows arm64 are not included in 0.1.0.

### Licensing

Proprietary freeware: free to use (personal, corporate internal, research,
production monitoring) and free to redistribute unmodified; no sale, no
modification, no reverse engineering. See `LICENSE.md`. The source code is
not distributed.

### Packaging

- The release binaries are **stripped** (symbol/debug information removed
  with the platform strip tool) and built with build-machine paths remapped
  to a neutral prefix, so no machine-local paths are embedded in the
  shipped binaries.
- Each release archive is **self-contained** for third-party compliance:
  `THIRD_PARTY_NOTICES.md` carries the component inventory plus the
  verbatim license and copyright texts collected from the cargo registry
  sources of all 299 locked packages (gaps are flagged in the file, not
  papered over).
- Checksum verification helpers (`scripts/verify-release.sh`,
  `scripts/verify-release.ps1`) resolve artifact paths relative to the
  `SHA256SUMS` file, so they work from any directory.

See `docs/VERIFY.md` for checksums and signature status, and
`docs/INSTALL.md` for installation instructions.
