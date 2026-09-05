# ltop

**ltop** (LLM top) is a single-binary, keyboard-only terminal dashboard that
monitors a local [llama.cpp](https://github.com/ggml-org/llama.cpp)
`llama-server` and the OS process behind it — read-only. It polls the
server's `/metrics`, `/slots` and `/props` endpoints plus local process
CPU/memory and renders an integrated dashboard. No daemon, Prometheus, or
Grafana required.

- **Developer / distributor / rights holder:** [@pauldckim](https://github.com/pauldckim)
- **License:** proprietary freeware (see [LICENSE.md](LICENSE.md)). The
  **source code is not distributed** and is not available from the
  distributor.
- **Current release:** [v0.1.0](https://github.com/pauldckim/ltop-release/releases/tag/v0.1.0) (2026-09-05)
  (staged; the release assets are pinned in
  [`releases/v0.1.0/SHA256SUMS`](releases/v0.1.0/SHA256SUMS) — see
  [docs/VERIFY.md](docs/VERIFY.md) for the current status)

## Screenshots

| 80×24 dashboard | Wide dashboard (120×40) |
|---|---|
| ![ltop 80x24 dashboard](assets/screenshots/ltop-80x24-dashboard.png) | ![ltop wide dashboard](assets/screenshots/ltop-120x40-wide.png) |

*Mock data: endpoint `http://localhost:8080`, mock PID 4242, model
`qwen3-4b-q4_k_m.gguf`.*

## Features

- **Integrated dashboard** — CPU, Memory, Inference, Slots and Server panels
  in one screen, keyboard-only, single binary.
- **Live inference view** — while a slot is processing, the Inference panel
  shows in-flight tokens and a live tok/s derived from `/slots` (the
  server's generated-token counters only move when a slot is released, so a
  `/metrics`-only view would show a frozen total and `0.0 tok/s`
  mid-stream). Idle totals are labeled `done: completed tasks only`; the
  composed total never double-counts.
- **Per-source status** — each source carries `fresh` / `stale` /
  `unavailable` / `disabled` with the last-success time; a failing source
  never masquerades as fresh and never takes down the rest of the dashboard.
- **`/metrics` awareness** — llama-server only serves `/metrics` when
  started with `--metrics`. Without it, the Inference source is marked
  *disabled* while the other sources keep updating.
- **Local vs remote endpoints** — OS process metrics are collected only for
  local endpoints (`localhost` / `127.0.0.1` / `::1`); for remote endpoints
  the process source is shown as disabled (N/A).
- **Themes** — tokyo-night (default), catppuccin-mocha, dracula, nord.
- **Responsive layout** — the two-column dashboard at ≥ 80×24 degrades to a
  stacked compact layout in smaller terminals without clipping or panics;
  the footer key hints pack atomically and the `@pauldckim` attribution
  stays pinned to the right.

## Platform support

| Platform | 0.1.0 artifact | Signing status |
|---|---|---|
| macOS x86_64 | `ltop-v0.1.0-macos-x86_64.zip` | **unsigned** — no Developer ID / notarization yet (see [docs/VERIFY.md](docs/VERIFY.md)) |
| Windows x86_64 | `ltop-v0.1.0-windows-x86_64.zip` | **unsigned** — no Authenticode yet (see [docs/VERIFY.md](docs/VERIFY.md)) |
| Linux x86_64 | `ltop-v0.1.0-linux-x86_64.tar.gz` | n/a (checksums only) — glibc dynamic build |

macOS arm64, Windows arm64 and Linux aarch64 are **not** included in 0.1.0.
The macOS and Windows binaries are plain CLI executables; no native
installer (MSI/PKG/DMG/RPM) is shipped — a single binary plus a checksum is
the complete install (see [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)).

All 0.1.0 binaries are **stripped** (symbol/debug information removed) and
built with build-machine paths remapped to a neutral prefix, so no
machine-local paths are embedded in the shipped binaries (see
[docs/VERIFY.md](docs/VERIFY.md)).

## Installation

Download the archive for your platform from the
[v0.1.0 release](https://github.com/pauldckim/ltop-release/releases/tag/v0.1.0),
verify the SHA-256 checksum ([docs/VERIFY.md](docs/VERIFY.md)), extract, and
put the binary on your `PATH`:

```sh
# macOS / Linux
unzip ltop-v0.1.0-macos-x86_64.zip        # or: tar xzf ltop-v0.1.0-linux-x86_64.tar.gz
install -m 0755 ltop-v0.1.0-macos-x86_64/ltop /usr/local/bin/ltop

# Windows (PowerShell)
Expand-Archive .\ltop-v0.1.0-windows-x86_64.zip
# then add the extracted folder to PATH, or run ltop.exe from it
```

Full per-OS instructions: [docs/INSTALL.md](docs/INSTALL.md).

> **Unsigned binaries.** The 0.1.0 macOS and Windows binaries are unsigned.
> On macOS, Gatekeeper will block first launch of an unsigned binary
> downloaded from the internet; on Windows, SmartScreen may show a warning.
> Verify the SHA-256 checksum first, then follow the platform notes in
> [docs/VERIFY.md](docs/VERIFY.md). These packages do **not** satisfy
> official Homebrew cask requirements (which need Developer ID +
> notarization) — see [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Usage

```sh
# Default: monitor http://localhost:8080, poll every 1s
ltop

# Explicit endpoint (flag or positional)
ltop --endpoint http://localhost:8081
ltop http://myserver:8081

# Polling interval in seconds (0.5..=10.0)
ltop --endpoint http://localhost:8081 --interval 2

# Monitor a specific local process PID
ltop --pid 4242

# Theme preset (tokyo-night | catppuccin-mocha | dracula | nord)
ltop --theme dracula
```

| Option | Description |
|---|---|
| `-e, --endpoint <URL>` | llama-server endpoint (conflicts with the positional endpoint) |
| `[ENDPOINT]` | positional endpoint (cannot be combined with `--endpoint`) |
| `-i, --interval <SECS>` | polling interval in seconds, finite `0.5..=10.0` (default `1`) |
| `-p, --pid <PID>` | target process PID (local endpoints only) |
| `--theme <NAME>` | theme preset name |
| `-h, --help` / `-V, --version` | help / version |

The endpoint defaults to `http://localhost:8080`. A bare `host:port` is
normalized to `http://host:port`; `http`/`https` are the only accepted
schemes. ltop requires a TTY; piped/redirected stdout is rejected cleanly
before any control sequence is emitted.

### Keyboard

| Key | Action |
|---|---|
| `q` / `Ctrl-C` | quit |
| `r` | immediate refresh (coalesced) |
| `+` / `-` | increase / decrease polling interval (clamped to 0.5–10 s) |
| `Tab` / `Shift+Tab` | move panel focus (CPU → Memory → Inference → Slots → Server) |
| `t` / `T` | cycle theme forward / backward |

### Platform notes (N/A fields)

Process CPU% requires a time-differenced sample (the first sample is a
warm-up shown as N/A) and may exceed 100% on multi-core hosts; a
system-capacity-normalized 0–100% is shown alongside. Fields that are not
meaningful on a platform are shown as **N/A**, never as 0:

| Field | macOS | Windows | Linux |
|---|---|---|---|
| VIRT | N/A | reported | reported |
| Thread count | N/A | N/A | reported |

## License

ltop is distributed under a **proprietary freeware license**
([LICENSE.md](LICENSE.md)): free to use (personal, corporate internal,
research, production monitoring) and free to redistribute **unmodified**
with the license and notices intact; no sale, no modification, no reverse
engineering. It is **not** open source. Third-party components statically
linked into the binary are identified in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which is
**self-contained**: it carries the verbatim license and copyright texts
collected from the cargo registry sources of all 299 locked packages
(gaps are flagged in the file, not papered over). Canonical SPDX license
texts under [`third-party/licenses/`](third-party/licenses/) are a
supplemental reference, and a CycloneDX SBOM is at
[`sbom/ltop-v0.1.0.cdx.json`](sbom/ltop-v0.1.0.cdx.json).

## Security

- Read-only monitoring: ltop sends no data anywhere and opens no
  listening ports; it only reads HTTP endpoints you point it at and local
  process statistics.
- Report vulnerabilities via **GitHub private vulnerability reporting**
  for this repository (Settings → Security → Private vulnerability
  reporting). There is no public security email. See
  [docs/SECURITY.md](docs/SECURITY.md).
- Checksums and current signature status: [docs/VERIFY.md](docs/VERIFY.md).

## Development

ltop is developed by **@pauldckim**. This repository is a **binary-only
release repository**: it contains release artifacts (as GitHub Release
assets), manifests, documentation and packaging templates — **no source
code**. Source contributions cannot be accepted here; use the issue tracker
for bug reports, feature requests and packaging problems.
See [CONTRIBUTING.md](CONTRIBUTING.md).

### Repository layout

```
LICENSE.md              proprietary freeware license (ltop itself)
THIRD_PARTY_NOTICES.md  self-contained third-party notices: component
                        inventory + verbatim license/copyright texts
third-party/licenses/   canonical SPDX license texts (supplemental)
sbom/                   CycloneDX SBOM (generated from the dependency lock)
releases/<ver>/SHA256SUMS  tracked checksum manifest per release
docs/                   INSTALL, VERIFY, SECURITY, DISTRIBUTION
assets/screenshots/     dashboard screenshots (mock renderings)
homebrew/               Homebrew cask template (disabled until signed)
winget/                 WinGet manifest template (disabled until published/signed)
scripts/                public-safe packaging + checksum verification helpers
```
