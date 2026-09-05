# Verifying ltop releases

## Current status (read this first)

**v0.1.0 is staged, not yet published.** The public repository and the
GitHub Release with the archive assets do not exist yet. The archives live
in local staging (`dist/v0.1.0/`, gitignored) and the checksum manifest is
tracked at `releases/v0.1.0/SHA256SUMS`. The checksums below are the pinned
values of the **staged** archives; deterministic packaging (byte-identical
second run verified) means they will be the values of the published release
assets.

**Intended publishing policy:** when published, each version is a git tag
(`vX.Y.Z`) with a GitHub Release attached; the archives + `SHA256SUMS`
become release assets and are **never modified in place** — a changed
artifact means a new version (or a new release with the old one
superseded). See [DISTRIBUTION.md](DISTRIBUTION.md) §1 and §3.

## Checksums

Verify the archive you downloaded **before** running it.

### v0.1.0 (2026-09-05; repackaged 2026-09-06 with stripped binaries)

| Artifact | SHA-256 |
|---|---|
| `ltop-v0.1.0-macos-x86_64.zip` | `e4d60310db4f638f9cf01e182be1bc35e1b39678e0dcf9d7c260e2a84b7a5b42` |
| `ltop-v0.1.0-windows-x86_64.zip` | `56731ea57a8aff8f8ffc07229aedb9810b6f7e534def0f7ea26ccd4228dab572` |
| `ltop-v0.1.0-linux-x86_64.tar.gz` | `f940cf94a1023f4764a82f8e4bda5c075a09f1407baccaeeb4527574ad3f8722` |

The binaries are the **final stripped release binaries** (see "Binary
quality" below), produced on each source platform from the verified final
source and verified by hash before packaging:

| Binary | Size (bytes) | SHA-256 |
|---|---|---|
| macOS x86_64 `ltop` | 4,494,724 | `9e67b47cdfeb7448bdaec8e265e5494e4b8dbdf5c30257d8c85e974ebc068ebd` |
| Windows x86_64 `ltop.exe` | 4,653,056 | `a6ddcc0b2a9efcde5333cb3e58cbcac9a2ac4acfe4ef7570e6e622b55649e59e` |
| Linux x86_64 `ltop` | 4,931,496 | `e18a3f0e9ea2e61ec5a44d5ab54256b774aec83a7d2ab4cf9e2f0df91daff089` |

**Binary quality (0.1.0):** the shipped binaries are **stripped** — symbol
and debug information removed with the platform tool (macOS `strip`, Linux
`strip --strip-all`, Windows cargo release output with
`profile.release.strip=symbols`) — and built with the build machine's home
directory remapped to a neutral prefix
(`--remap-path-prefix`), so **no build-machine paths** (no `~/.cargo`
registry paths, no user home, no internal hosts) are embedded in the
binaries. Functionality is re-verified after stripping on each source
platform (`--version` + a console/PTY `q` smoke). The binaries are unsigned
at 0.1.0, so stripping has no signature impact now; any future
signed/notarized release must be signed **after** stripping.

These values are recorded in `releases/v0.1.0/SHA256SUMS` (tracked) and
`dist/v0.1.0/SHA256SUMS` (local staging); each archive's `README.txt`
carries its binary's hash.

### How to verify

Once published, download the release `SHA256SUMS` asset next to your
archive, then:

```sh
# macOS
shasum -a 256 -c SHA256SUMS

# Linux
sha256sum -c SHA256SUMS
```

```powershell
# Windows (PowerShell)
(Get-FileHash .\ltop-v0.1.0-windows-x86_64.zip -Algorithm SHA256).Hash
```

This repository also ships helper scripts that verify a `SHA256SUMS` file
against local archives: `scripts/verify-release.sh` (macOS/Linux, POSIX sh)
and `scripts/verify-release.ps1` (Windows, PowerShell 5.1+). Both resolve
the listed artifact paths **relative to the directory containing the
SHA256SUMS file**, so they work from any current directory:

```sh
# from the repository root:
sh scripts/verify-release.sh dist/v0.1.0/SHA256SUMS

# from the directory that holds the archives:
cd dist/v0.1.0
sh ../../scripts/verify-release.sh SHA256SUMS
```

```powershell
# from the repository root:
.\scripts\verify-release.ps1 -SumsFile .\dist\v0.1.0\SHA256SUMS
```

## Signature status (0.1.0)

**The 0.1.0 binaries are unsigned.** There is no code signature and no
checksum signature to verify against yet:

| Platform | Status | What it means |
|---|---|---|
| macOS | not signed, not notarized | Gatekeeper treats the binary as an unidentified developer (see [INSTALL.md](INSTALL.md) for the post-checksum workaround) |
| Windows | not Authenticode-signed | SmartScreen shows the unknown-publisher prompt |
| Linux | n/a | checksum verification only |

### Why self-signed certificates are not enough for public distribution

A self-signed code-signing certificate (one you generate yourself) only
proves integrity **in environments that already trust you**:

- **macOS** — Gatekeeper and notarization require a certificate issued by
  **Apple** (Developer ID, via the paid Apple Developer Program) plus
  submission to Apple's notary service. A self-signed certificate is not
  accepted; the binary is still blocked for ordinary users.
- **Windows** — public SmartScreen reputation requires a certificate from a
  trusted **certificate authority** (e.g. DigiCert, Sectigo, GlobalSign) or
  Microsoft's Azure Artifact Signing / Store distribution. A self-signed
  certificate is only honored on machines where you have explicitly
  installed it into the trusted root store — i.e. developer machines or
  enterprise-managed fleets, not the general public.

Self-signed signing is therefore useful for **internal/enterprise-managed
environments** (integrity + tamper evidence on machines you control), but it
does **not** satisfy public trust requirements, and the 0.1.0 packages do
**not** satisfy official Homebrew cask requirements (Developer ID +
notarization). See [DISTRIBUTION.md](DISTRIBUTION.md) for the planned
signing work.

## What is verified today

- SHA-256 checksums of every staged archive (this file +
  `releases/v0.1.0/SHA256SUMS` + `dist/v0.1.0/SHA256SUMS`), and of the
  binaries inside them.
- Binary quality: the shipped binaries are stripped and carry
  **no build-machine paths** (verified by byte scan on each source
  platform and after extraction), and each was re-verified natively on its
  source platform after packaging: archive extraction, binary hash,
  `ltop --version`, and a console/PTY `q` smoke (clean exit 0).
- The archives contain exactly: the binary, `LICENSE.md`,
  `THIRD_PARTY_NOTICES.md`, `README.txt` — nothing else; **no source code,
  no scripts, no machine-local paths**.
- `THIRD_PARTY_NOTICES.md` is self-contained: verbatim license and
  copyright texts collected from the cargo registry sources of all 299
  locked packages (151 distinct texts; gaps flagged, not papered over).
- Deterministic packaging: a second packaging run from the same inputs
  produced byte-identical archives.
- Screenshot validation (programmatic only, see below).

**Publishing (intended, not yet done):** when the release is published, the
archives + `SHA256SUMS` become assets of the immutable `v0.1.0` GitHub
Release and are never modified in place (see the policy at the top of this
file). Until then, verification is against the staged archives and the
tracked checksum manifest.

## Screenshot validation (programmatic)

The dashboard screenshots in `assets/screenshots/` are **mock renderings**
produced by a deterministic generator (fixed 5×7 bitmap font, fixed Tokyo
Night palette, mock data only: endpoint `http://localhost:8080`, mock PID
4242, model `qwen3-4b-q4_k_m.gguf`). They were validated
**programmatically only** — no visual or aesthetic review was performed:

| Check | Result |
|---|---|
| PNG signature, per-chunk CRCs, IHDR/IDAT/IEND order | PASS (2/2) |
| Dimensions: 1440×576 (80×24 char grid at 18×24 px/cell) and 2160×960 (120×40) | PASS (2/2) |
| 8-bit RGB, non-interlaced; decoded pixel buffer size consistent with IHDR | PASS (2/2) |
| Non-uniform pixels: 10 distinct colors; background (RGB 26,27,38) is exactly 501,480/829,440 (60.4601%) of pixels in the 80×24 image and 1,356,543/2,073,600 (65.4197%) in the 120×40 image | PASS (2/2) |
| Byte-identical to a fresh deterministic regeneration — proves the content is exactly the mock grid described above (mock-only data) | PASS (2/2) |

Known renderer property: the inter-cell gap (one column/row of the 6×8
pixel cell grid) is rendered black (RGB 0,0,0) instead of the background
color — exactly 13/48 of all pixels (27.0833%) in both images (224,640/
829,440 and 561,600/2,073,600). Aesthetics were not assessed.
