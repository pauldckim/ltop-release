# Changelog

All notable public changes to ltop releases are recorded here.

## Installer channel: `install-v2` — 2026-09-07 (published)

**Installer channel, not a product version.** The product releases are the
`vX.Y.Z` tags above; this entry records the hardened one-line installer
pinned at the tag
[`install-v2`](https://github.com/pauldckim/ltop-release/tree/install-v2).
No product artifact changed: the installer downloads and verifies the
existing published releases (macOS v0.1.1, Linux v0.1.0). The previous
channel [`install-v1`](https://github.com/pauldckim/ltop-release/tree/install-v1)
is **superseded but remains published and immutable** (never moved).

Hardening over `install-v1` (each with adversarial regression tests in
`scripts/tests/test-install.sh`):

- **Interrupts (F1):** SIGINT/SIGTERM traps clean up the temporary
  workspace and the staged file, print a clear "interrupted" message, and
  exit with the conventional code (130/143); nothing is left
  half-installed.
- **Hashing (F2):** SHA-256 digests are computed from a private temp file
  via stdin, so the hash tool never sees the original file name (no GNU
  coreutils backslash-escaping of file names) and an unreadable file
  fails the hash instead of yielding an empty digest; the tool's exit
  status is preserved and the digest is validated.
- **Prefix canonicalization (F3):** every symlink component of
  `--prefix` is resolved (portable; bounded against symlink loops) and
  the resolved path is re-checked against the unsafe-prefix list, so a
  symlinked prefix cannot alias a write into an unsafe system directory;
  benign aliases (e.g. `/tmp` → `/private/tmp` on macOS) are resolved
  and used.
- **No downgrade (F4):** `curl` runs with `--proto '=https'` in
  production (refuses any redirect hop to a non-HTTPS URL); the `wget`
  fallback adds `--https-only` / `--secure-protocol=TLSv1_2` on builds
  that support them and inspects every redirect hop it prints — a foreign
  intermediate hop is refused even when the final URL is allowed.
  Documented limitation: a downloader exposing neither its redirect hops
  nor a no-downgrade flag cannot be fully chain-audited; the four-hash
  pipeline remains the binding guarantee.
- **Test-only platform override (F5):** the v1 `LTOP_INSTALL_PLATFORM`
  hook is removed (setting it is an error); the replacement
  `LTOP_INSTALL_TEST_PLATFORM` is honored only together with
  `LTOP_INSTALL_TEST_MANIFEST`, so a leaked platform variable alone can
  never select a different architecture in production.
- **Dry-run (F6):** `--dry-run` reports the resolved existing-target
  state (no-op / would stop / would replace / would create) without
  prompting or changing anything.

## Installer channel: `install-v1` — 2026-09-07 (superseded by install-v2; published and immutable)

**Installer channel, not a product version.** The product releases are the
`vX.Y.Z` tags above; this entry records the original one-line installer
pinned at the tag
[`install-v1`](https://github.com/pauldckim/ltop-release/tree/install-v1).
No product artifact changed: the installer downloads and verifies the
existing published releases (macOS v0.1.1, Linux v0.1.0).

- **`install.sh` (repository root):** POSIX sh one-line installer for
  macOS (arm64/x86_64, Rosetta-aware) and Linux (x86_64). HTTPS-only
  downloads (TLS ≥ 1.2, `curl` preferred / `wget` fallback, redirect host
  restricted to the release hosts), four embedded SHA-256 checks before
  anything is installed (archive, `SHA256SUMS` file, the archive line in
  that file, extracted binary), atomic install (temp file + `chmod 0755` +
  `mv`) to `$HOME/.local/bin` by default. No sudo, no shell rc changes, no
  services. Options: `--prefix`, `--force`, `--uninstall`, `--dry-run`,
  `--quiet`, `--help`. Idempotent on the expected binary; refuses foreign
  or older files non-interactively unless `--force` (interactive prompt
  otherwise); `--uninstall` removes only known ltop hashes.
- **`scripts/tests/test-install.sh`:** deterministic loopback-fixture test
  suite for the installer (mapping, hash pipeline, download failures,
  redirect rejection, consent paths, symlinks, uninstall, dry-run, spaces,
  PATH hint, cleanup, no rc mutation, piped-script safety).
- **Docs:** README/INSTALL/VERIFY/DISTRIBUTION updated; the review-first
  alternative to `curl | sh` (fetch, hash-verify, run) is documented in
  [docs/VERIFY.md](docs/VERIFY.md). Windows installation is unchanged
  (PowerShell steps in [docs/INSTALL.md](docs/INSTALL.md)).

## 0.1.1 — 2026-09-06 (published)

**Adds Apple Silicon (arm64) support for all M1–M5 Macs** and rebuilds
the macOS x86_64 artifact at the new version. No product behavior
changes: the Rust source delta is the version bump only (plus a
test-only Python-compatibility change in the certification scripts,
which is not shipped in the binaries). 0.1.1 is macOS-only:
the published 0.1.0 Windows and Linux assets remain the current release
for those platforms and are unchanged.

### Platforms

| Platform | Artifact | Notes |
|---|---|---|
| macOS arm64 (Apple Silicon) | `ltop-v0.1.1-macos-arm64.zip` | **new** — one generic `aarch64-apple-darwin` target covers M1–M5: default rustc codegen (CPU `apple-m1`, the Apple Silicon baseline; no `target-cpu`/`target-feature` overrides, never `native`), `MACOSX_DEPLOYMENT_TARGET=11.0` (Big Sur — the arm64 floor, so the binary runs on every Apple Silicon Mac). **Ad-hoc signed** (required for arm64 launch). |
| macOS x86_64 (Intel) | `ltop-v0.1.1-macos-x86_64.zip` | rebuilt at 0.1.1 with the identical procedure (path remap + strip + ad-hoc sign); **ad-hoc signed** for consistency with the arm64 artifact |
| Windows x86_64 | `ltop-v0.1.0-windows-x86_64.zip` | unchanged — the published 0.1.0 asset remains the current Windows release |
| Linux x86_64 | `ltop-v0.1.0-linux-x86_64.tar.gz` | unchanged — the published 0.1.0 asset remains the current Linux release |

### Signing status (0.1.1)

Both 0.1.1 macOS binaries are **ad-hoc signed** (`codesign -dv` shows
`Signature=adhoc`). The arm64 binary must carry at least an ad-hoc
signature to launch on Apple Silicon (an unsigned arm64 binary is killed
at launch); the x86_64 binary is ad-hoc signed for consistency. **Ad-hoc
signing is not a Developer ID signature:** neither binary is
Developer-ID signed or notarized, so a quarantined first run (e.g. a
browser or Homebrew download) is still blocked by Gatekeeper — verify
the SHA-256 checksum first, then follow the unblock procedure in
[docs/INSTALL.md](docs/INSTALL.md) / [docs/VERIFY.md](docs/VERIFY.md).
Developer ID + notarization remains the planned proper fix.

### Certification

- **macOS arm64:** certified on an Apple M4 Max (macOS 26.6.2, arm64)
  with the full 33-gate live certification — **33/33 gates PASS**
  (0 FAIL / 0 SKIPPED / 0 N-A), including a real llama-server (pinned
  commit, CPU-only build) with the pinned model, the full TUI key/resize/
  restart/remote-semantics gates, and a 300 s soak (59 completions,
  bounded RSS growth, clean exit, no leftover processes). The native
  cargo gates (384 tests) and the Python certification suite (62 tests)
  also pass on the M4. Sanitized summary:
  [docs/VERIFY.md](docs/VERIFY.md) § "Certification (0.1.1)".
- **macOS x86_64:** built and gated on the same Intel macOS VM as the
  arm64 cross-build (384 cargo tests + Python suites); the stripped,
  ad-hoc-signed binary is re-verified after signing (`--version`, PTY
  `q` smoke, system-library linkage, machine-path scan) and the
  extracted release archive is installed and run end-to-end through the
  Homebrew cask path on the Intel VM.
- The 0.1.0 certification records (author host, Intel macOS VM 33/33,
  Windows VM) remain the durable evidence for the 0.1.0 artifacts.

### Packaging

- Same deterministic packaging as 0.1.0: one top-level directory per
  archive (`ltop-v0.1.1-macos-arm64/`, `ltop-v0.1.1-macos-x86_64/`)
  containing exactly the binary, `LICENSE.md`, `THIRD_PARTY_NOTICES.md`,
  `README.txt`; fixed timestamps (2026-09-06 UTC), sorted entries, zeroed
  owners; a second packaging run produced byte-identical archives.
- `THIRD_PARTY_NOTICES.md` component inventory unchanged from 0.1.0
  (same 299-package dependency lock); the SBOM is regenerated for 0.1.1
  at [`sbom/ltop-v0.1.1.cdx.json`](sbom/ltop-v0.1.1.cdx.json).
- Homebrew own-tap cask (`pauldckim/tap`) updated to 0.1.1 with
  per-architecture URL/checksum selection (`arch arm: "arm64",
  intel: "x86_64"`); the 0.1.0 x86_64-only architecture requirement is
  removed. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) §5.

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
