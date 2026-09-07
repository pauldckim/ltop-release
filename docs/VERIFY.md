# Verifying ltop releases

## Current status (read this first)

**v0.1.2 is staged (2026-09-08), publication pending.** v0.1.2 is the
first release shipping **all four platforms** (macOS arm64, macOS
x86_64, Windows x86_64, Linux x86_64): API key authentication
(`--api-key-file` / `LTOP_API_KEY`) and the Linux process-discovery fix.
The staged archives are pinned below and in
`releases/v0.1.2/SHA256SUMS`; the `v0.1.2` tag and GitHub Release are
created at publication, and the archives are attached to the release
then. Until publication the current published releases remain v0.1.1
(macOS) and v0.1.0 (Windows/Linux).

**v0.1.1 was published on 2026-09-06.** v0.1.1 adds macOS arm64
(Apple Silicon) and rebuilds macOS x86_64 at the new version; it is
**macOS-only** — the published v0.1.0 Windows and Linux artifacts
remain the current release for those platforms. The v0.1.1 checksums
are pinned below and in `releases/v0.1.1/SHA256SUMS`; the archives are
attached to the
[v0.1.1 GitHub Release](https://github.com/pauldckim/ltop-release/releases/tag/v0.1.1).
The release assets are never modified in place after publication.

**v0.1.0 was published on 2026-09-06.** Download the archives and
`SHA256SUMS` from the
[GitHub Release](https://github.com/pauldckim/ltop-release/releases/tag/v0.1.0).
The checksum manifest is also tracked at
`releases/v0.1.0/SHA256SUMS`. The published assets were downloaded again
after publication and verified byte-for-byte against the staged artifacts.

**Publishing policy:** each version is a git tag
(`vX.Y.Z`) with a GitHub Release attached; the archives + `SHA256SUMS`
become release assets and are **never modified in place** — a changed
artifact means a new version (or a new release with the old one
superseded). The one-line installer lives on its own channel tag
(`install-v2`, current; `install-v1` is superseded but remains published
and immutable — both are channel tags, never moved) and is documented in
[DISTRIBUTION.md](DISTRIBUTION.md) §5.1. See
[DISTRIBUTION.md](DISTRIBUTION.md) §1 and §3.

## Installer (tag `install-v2`)

The one-line installer is pinned at the tag
[`install-v2`](https://github.com/pauldckim/ltop-release/tree/install-v2)
(installer channel — **not** a product version; the `vX.Y.Z` product tags
are unchanged and immutable). The previous channel
[`install-v1`](https://github.com/pauldckim/ltop-release/tree/install-v1)
remains published and immutable (superseded: it predates the install-v2
hardening — interrupt cleanup with exit 130/143, stdin-based hash
verification, symlink-canonicalized prefix checks, wget no-downgrade
flags + redirect-chain inspection, and the test-only platform override).
Both channels pin the same product releases (macOS v0.1.1, Linux v0.1.0).

**Next channel (staged):** the `install.sh` on `main` has been updated to
pin the staged **v0.1.2** artifacts (macOS arm64/x86_64 and Linux
x86_64 — all three platforms at v0.1.2, sharing the v0.1.2
`SHA256SUMS`) and is staged as the next installer channel, `install-v3`.
The `install-v3` tag is created after the v0.1.2 publication and the
one-liner in this document, the README and INSTALL.md is repointed in a
follow-up commit; until then the published `install-v2` one-liner
remains valid and installs the current published releases. The updated
script passes its deterministic test suite on a macOS host and a Linux
host (loopback fixtures only; see "What is verified today" below).

| File | SHA-256 |
|---|---|
| `install.sh` (at `install-v2`) | `8e8131c1892a06e74a7ff87a2349db337fe72f89e1309c38e41f47259c5c4a43` |
| `install.sh` (at `install-v1`, superseded) | `bee9538e81266d268bdd8765abf52a1686fe017d6bd0383b0bf7eaf54d280b81` |

Verify the script before executing it (review-first alternative to
`curl | sh`):

```sh
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/pauldckim/ltop-release/install-v2/install.sh \
  -o /tmp/ltop-install.sh
# macOS
shasum -a 256 /tmp/ltop-install.sh
# Linux
sha256sum /tmp/ltop-install.sh
# expected: 8e8131c1892a06e74a7ff87a2349db337fe72f89e1309c38e41f47259c5c4a43
sh /tmp/ltop-install.sh
```

The script embeds the SHA-256 values of the pinned artifacts (archive,
`SHA256SUMS` file, extracted binary) for every supported platform; the
embedded archive hashes are the published release hashes below, and the
embedded `SHA256SUMS` file hashes are:

| File | SHA-256 |
|---|---|
| `SHA256SUMS` of the v0.1.1 release | `79568789220e644d690bb1ef6c4091f126053a9a8f9670f4046f20775d4e6e12` |
| `SHA256SUMS` of the v0.1.0 release | `6d5a9a753cdc272cf9284fa8b9ed3ea13f12028847804c3be4e66f01e910821c` |

The installer's deterministic test suite
(`scripts/tests/test-install.sh`, loopback fixtures only) covers the
platform mapping, all hash checks, download failures, redirect-host
rejection, idempotency, foreign-file refusal, `--force`, the interactive
prompt, symlink handling, uninstall (known/foreign), `--dry-run`, spaced
paths, PATH hints, cleanup, and the no-shell-rc-mutation property, plus
the install-v2 hardening: SIGINT/SIGTERM mid-download (interrupted
message, exit 130/143, cleanup), backslash-path hashing and unreadable
existing files, symlinked-prefix canonicalization (unsafe alias refused,
benign alias resolved, symlink loop refused), redirect-chain inspection
(a foreign intermediate hop is refused even when the final URL is
allowed), HTTPS-downgrade rejection, and the test-only platform override
(a leaked platform variable without a test manifest is refused).

## Checksums

Verify the archive you downloaded **before** running it.

### v0.1.2 (staged 2026-09-08; publication pending — all four platforms)

| Artifact | SHA-256 |
|---|---|
| `ltop-v0.1.2-macos-arm64.zip` | `d349b64375fb8263011a625c5f585db0930affdf2c0d0c3e2deb268d84780b47` |
| `ltop-v0.1.2-macos-x86_64.zip` | `0fe80dfdb36616059a56a645c3d3eeddf1bd5257150e48141fb063b0b77f2c7c` |
| `ltop-v0.1.2-windows-x86_64.zip` | `283cab4b15969a44ca15fabee2faa028ae42d83b1dae27343d63704c29e1f86c` |
| `ltop-v0.1.2-linux-x86_64.tar.gz` | `f11144035a054c0c944f648045a25d5bc68e1def2236b7ed60cc6179bcb56bba` |

The binaries are the **final stripped release binaries** (macOS
ad-hoc-signed, per the F1 order build → re-verify → strip → sign → final
hash), verified by hash after transfer and before packaging:

| Binary | Size (bytes) | SHA-256 |
|---|---|---|
| macOS arm64 `ltop` (ad-hoc signed) | 4,354,928 | `a8f8ab16ec7e37c8121b86d7966c47fa1ba4292933696f068d11a33b6b1a9a0c` |
| macOS x86_64 `ltop` (ad-hoc signed) | 4,570,256 | `24362c464980074810762ec626b80e33aa98bac6743179462bbe5452dce69546` |
| Windows x86_64 `ltop.exe` (unsigned) | 4,683,264 | `b5d18dfee508680d25368e99067e8f3d557a5c16048b6a6663526e6ee6f8cf65` |
| Linux x86_64 `ltop` (unsigned) | 4,958,536 | `84a84b7c56e399f9178703da71be8894f02a394fef2ce36d1e01f5d3e41414c4` |

**Binary quality (0.1.2):** same as 0.1.1 — **stripped** (macOS `strip`,
Linux `strip --strip-all`, Windows `profile.release.strip=symbols`) and
built with the build machine's home directory remapped to a neutral
prefix (`--remap-path-prefix`), so **no build-machine paths** are
embedded (machine-path byte scan: zero occurrences in all four
binaries). The macOS binaries link only the 5 macOS system
dylibs/frameworks; the arm64 binary carries `LC_BUILD_VERSION` minos
11.0.0 (the arm64 floor, `MACOSX_DEPLOYMENT_TARGET=11.0`) and the
x86_64 binary keeps the recorded Mach-O minimum. The Linux binary is a
glibc dynamic build.

**Toolchain (0.1.2, exact per artifact):** rustc **1.98.0**
(commit `88d9e12ae`) for the macOS arm64 and x86_64 artifacts — the
pinned baseline, no deviation; rustc **1.98.1** (commit `48a229cea`)
for the Windows and Linux artifacts — a recorded deviation from the
1.98.0 pin (a release may use a newer compiler only with the exact
`rustc --version` recorded per artifact; the compiler identity was
fingerprinted from the shipped binaries and matches the build-host
records).

**Packaging (0.1.2):** deterministic — a second packaging run from the
same inputs produced byte-identical archives (fixed 2026-09-08 UTC
timestamps, sorted entries, zeroed owners); each archive contains
exactly the binary, `LICENSE.md`, `THIRD_PARTY_NOTICES.md`, `README.txt`
(no source, no scripts, no machine paths); zip entry modes are binary
0755 / others 0644 (no exec bit on the Windows zip); extracted binary
hashes equal the staging hashes above. These values are recorded in
`releases/v0.1.2/SHA256SUMS` (tracked; the staged copy in `dist/v0.1.2/`
is byte-identical); the `SHA256SUMS` file's own SHA-256 is
`3a76bbfcc4df41f617fb7149ee74927c5897fae6a67cad40103dfb779ee22850`.

### v0.1.1 (published 2026-09-06; macOS only)

| Artifact | SHA-256 |
|---|---|
| `ltop-v0.1.1-macos-arm64.zip` | `66c97f41f4a0c9919b89f8a003366a36f8e77d79af03ec866dccb3efbaa9fa55` |
| `ltop-v0.1.1-macos-x86_64.zip` | `676da4356e00813e35092c8f386daa78ee41cca09a8f033949ca452135e5bdd9` |

The binaries are the **final stripped, ad-hoc-signed release binaries**,
produced on the Intel macOS VM from the verified final 0.1.1 source
(arm64 cross-built, x86_64 rebuilt) and verified by hash before and after
transfer, before packaging:

| Binary | Size (bytes) | SHA-256 |
|---|---|---|
| macOS arm64 `ltop` (ad-hoc signed) | 4,554,192 | `19a6e42346f05dc37dd00f9ff723408d870237b72dc7a9cd77245069f443401a` |
| macOS x86_64 `ltop` (ad-hoc signed) | 4,795,968 | `00933d50ef9ca133d788f0a1d883f1ab71dd0acacfc6cf9eb0c2b89c4fba6cbd` |

**Binary quality (0.1.1):** same as 0.1.0 — **stripped** (macOS `strip`)
and built with the build machine's home directory remapped to a neutral
prefix (`--remap-path-prefix`), so **no build-machine paths** are embedded
(machine-path byte scan: zero occurrences in both binaries). Both link
only the 5 macOS system dylibs/frameworks. The arm64 binary is built with
default `aarch64-apple-darwin` codegen (rustc default CPU `apple-m1`, the
M1–M5 baseline; no `target-cpu`/`target-feature` overrides) and
`MACOSX_DEPLOYMENT_TARGET=11.0` (`otool -l`: `LC_BUILD_VERSION`, minos
11.0.0, platform MACOS) — it runs on every Apple Silicon Mac. The x86_64
binary keeps the 0.1.0 Mach-O minimum (10.12, `LC_VERSION_MIN_MACOSX`), so
the 0.1.0 → 0.1.1 x86_64 delta is the version string plus the ad-hoc
signature (see "Signature status (0.1.1)" below).

These values are recorded in `releases/v0.1.1/SHA256SUMS` (tracked); each
archive's `README.txt` carries its binary's hash.

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

Download the release `SHA256SUMS` asset next to your archive, then:

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

## Signature status (0.1.2)

| Platform | Status | What it means |
|---|---|---|
| macOS (arm64 + x86_64) | **ad-hoc signed** (`Signature=adhoc`) | same as 0.1.1: the arm64 binary must carry at least an ad-hoc signature to launch on Apple Silicon; the x86_64 binary is ad-hoc signed for consistency. **Not** a Developer ID signature — a quarantined first run is still blocked by Gatekeeper (verify the SHA-256 first, then the unblock procedure in [INSTALL.md](INSTALL.md)) |
| Windows | **unsigned** (no Authenticode) | SmartScreen shows the unknown-publisher prompt (same as 0.1.0) |
| Linux | n/a | checksum verification only |

Developer ID + notarization (macOS), Authenticode (Windows) and
GPG-signed checksums (Linux) remain the planned fixes
([DISTRIBUTION.md](DISTRIBUTION.md) §4).

## Signature status (0.1.1)

**The 0.1.1 macOS binaries are ad-hoc signed** (`codesign -dv` shows
`Signature=adhoc`, `flags=0x2(adhoc)`). Per architecture:

| Binary | Signing | Why |
|---|---|---|
| macOS arm64 | ad-hoc signed | **required**: on Apple Silicon every executable must carry at least an ad-hoc signature to launch (an unsigned arm64 binary is killed at launch) |
| macOS x86_64 | ad-hoc signed | for consistency with the arm64 artifact (x86_64 can launch unsigned; the 0.1.0 x86_64 binary was unsigned) |

**Ad-hoc signing is NOT a Developer ID signature.** Neither binary is
Developer-ID signed or notarized, and an ad-hoc signature does not satisfy
Gatekeeper for quarantined items: a quarantined first run (browser or
Homebrew download) is still blocked exactly like the unsigned 0.1.0
binaries. Verify the SHA-256 checksum first, then use the unblock
procedure in [INSTALL.md](INSTALL.md) (recursive `xattr -dr` before first
run, or System Settings → Privacy & Security → "Open Anyway"). Developer
ID + notarization remains the planned proper fix (§ "Signature status
(0.1.0)" / [DISTRIBUTION.md](DISTRIBUTION.md) §4).

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

**v0.1.2 (staged 2026-09-08, publication pending):**

- SHA-256 checksums of all four staged archives (this file +
  `releases/v0.1.2/SHA256SUMS`), and of the binaries inside them
  (verified after transfer, before packaging, and after extraction from
  all four archives).
- Binary quality: all four binaries stripped, machine-path byte scan
  with zero occurrences, `ltop --version` → `ltop 0.1.2` (exit 0);
  macOS ad-hoc signature verified (`codesign -dv` → `Signature=adhoc`),
  arm64 deployment target minos 11.0.0; exact compiler identity per
  artifact recorded ("Checksums" above).
- The archives contain exactly: the binary, `LICENSE.md`,
  `THIRD_PARTY_NOTICES.md`, `README.txt` — nothing else; the notices
  carry the 0.1.2 header and the unchanged 299-component inventory.
- Deterministic packaging: a second packaging run from the same inputs
  produced byte-identical archives (fixed 2026-09-08 UTC timestamps,
  sorted entries, zeroed owners).
- `THIRD_PARTY_NOTICES.md` component inventory unchanged from
  0.1.0/0.1.1 (same 299-package dependency lock); the SBOM is
  regenerated for 0.1.2 at
  [`../sbom/ltop-v0.1.2.cdx.json`](../sbom/ltop-v0.1.2.cdx.json)
  (299 components, identical set).
- Homebrew cask (staged): `Casks/ltop.rb` in the tap and the
  `homebrew/Casks/ltop.rb.template` mirror are generated for 0.1.2 with
  per-architecture URL/checksum selection; `ruby -c`, stub-DSL
  evaluation for both simulated architectures, `brew style --cask`,
  `brew audit --cask` and `brew info --cask` (Homebrew 6.0.22) all pass.
  The cask is committed/pushed to the tap **after** the v0.1.2 GitHub
  Release exists (the cask URL must resolve).
- WinGet (staged): the 0.1.2 three-file manifest set
  (`winget/manifests/p/pauldckim/ltop/0.1.2/`) was generated from the
  0.1.0 template with the scheduled v0.1.2 asset URL and the staged
  archive hash; `winget validate` passed on a Windows host (winget
  v1.29.290, 2026-09-08: "Manifest validation succeeded", no warnings).
  No external PR is submitted before publication.
 - Installer (staged as the `install-v3` channel): the updated
   `install.sh` (v0.1.2 mapping for all three platforms, v0.1.2
   known-binary/uninstall hashes) passes its deterministic test suite on
   a macOS host (144 tests, 0 failed, 2 skipped — wget absent) and a
   Linux host (149 tests, 0 failed, 0 skipped); loopback fixtures only.
- M4 arm64 native run: the shipped arm64 binary was executed on the
  Apple M4 Max certification host (macOS 26.6.2, arm64) — identity hash
  match with the staged record (`a8f8ab16…`), `file` → Mach-O arm64,
  minos 11.0.0, exactly the 5 system dylibs/frameworks, ad-hoc
  signature, `ltop --version` → `ltop 0.1.2`, native PTY `q` smoke, and
  10/10 loopback mock endpoint checks (see "Certification (0.1.2)"
  below).
- Certification: the full 33-gate live certification passed on the
  Apple M4 Max (macOS 26.6.2, arm64), finalized (see
  "Certification (0.1.2)" below).

**v0.1.1 (published 2026-09-06):**

- SHA-256 checksums of both published archives (this file +
  `releases/v0.1.1/SHA256SUMS`), and of the binaries inside them
  (verified on the build VM before transfer, after transfer, and after
  extraction from both archives).
- Binary quality: both binaries stripped, machine-path byte scan with
  zero occurrences, exactly the 5 macOS system dylibs/frameworks,
  `ltop --version` → `ltop 0.1.1` (exit 0), ad-hoc signature verified
  (`codesign -dv` → `Signature=adhoc`), arm64 deployment target minos
  11.0.0 (`LC_BUILD_VERSION`, platform MACOS).
- The archives contain exactly: the binary, `LICENSE.md`,
  `THIRD_PARTY_NOTICES.md`, `README.txt` — nothing else.
- Deterministic packaging: a second packaging run from the same inputs
  produced byte-identical archives (fixed 2026-09-06 UTC timestamps,
  sorted entries, zeroed owners).
- Extracted-archive runs: the x86_64 archive binary was run
  end-to-end through the Homebrew cask install path on the Intel macOS
  VM (download from a local server, SHA-256 verified by Homebrew,
  quarantine set, blocked first run, `xattr -dr` unblock, `--version`,
  PTY `q` smoke, clean uninstall) and directly on the author host
  (`--version` + PTY `q` smoke); the arm64 archive binary was extracted
  and run on the Apple Silicon certification host (`--version` + PTY
  `q` smoke, hash match with the build VM).
- Homebrew cask (0.1.1): per-architecture URL/checksum selection
  verified by definition-level checks (`brew style`, `brew audit`,
  `brew info`) and stub-DSL evaluation for both simulated architectures;
  the intel branch installed end-to-end from local assets before
  publication on the Intel macOS VM. The arm branch's *artifact* was
  verified on the Apple Silicon host by direct extraction/run; a full
  arm-branch `brew install` requires Homebrew on that host (not
  installed — non-admin machine) and is recorded N/A with that reason.
- Certification on Apple Silicon: the full 33-gate live certification
  passed on the M4 Max (see "Certification (0.1.1)" below).

**v0.1.0 (published 2026-09-06):**

- SHA-256 checksums of every published archive (this file +
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
- Homebrew own-tap cask: `pauldckim/tap` (repository
  `pauldckim/homebrew-tap`) pins the same `sha256`
  (`e4d60310db4f638f9cf01e182be1bc35e1b39678e0dcf9d7c260e2a84b7a5b42`)
  for `ltop-v0.1.0-macos-x86_64.zip`; the cask was installed end-to-end
  from the published release asset on macOS 15.7.8 and macOS 26.6.2
  (Homebrew 6.0.22) and the downloaded archive re-verified by hash
  (see `homebrew/README.md`).
- Screenshot validation: the dashboard screenshots are genuine Terminal
  captures; see the capture procedure and validation table below.

**Published verification:** the archives and `SHA256SUMS` are assets of the
`v0.1.0` and `v0.1.1` GitHub Releases. For both releases GitHub's reported
asset digests match the tracked manifests
(`releases/v0.1.0/SHA256SUMS`, `releases/v0.1.1/SHA256SUMS`), and
independently downloaded assets passed `SHA256SUMS` in full.
Published assets are never modified in place; changes require a new release.

## Certification (0.1.2, sanitized summary)

The 0.1.2 artifacts were built and certified on 2026-09-08. This is the
durable sanitized summary; the machine-local reports are not published
(same policy as the 0.1.0/0.1.1 records: no internal host names,
internal IPs, machine-local paths, or report file names in this
repository — hosts are referenced by role only).

**Build and toolchain (per artifact, exact):**

| Artifact | Toolchain | Notes |
|---|---|---|
| macOS arm64 + x86_64 | rustc **1.98.0** (commit `88d9e12ae`) — the pinned baseline, no deviation | F1 order: build → functional re-verify → strip → ad-hoc sign → final hash; arm64 cross-built with default `aarch64-apple-darwin` codegen + `MACOSX_DEPLOYMENT_TARGET=11.0`, x86_64 rebuilt with the identical procedure |
| Windows x86_64 | rustc **1.98.1** (commit `48a229cea`) — **recorded deviation** from the 1.98.0 pin (the exact version is recorded per artifact, as the pin rule requires) | MSVC build, `profile.release.strip=symbols`; unsigned (no Authenticode yet) |
| Linux x86_64 | rustc **1.98.1** (commit `48a229cea`) — **recorded deviation** from the 1.98.0 pin (same as above; identity fingerprinted from the shipped binary) | glibc dynamic build, `strip --strip-all`; unsigned (checksums only) |

**Deterministic gates per platform (0.1.2 source, `cargo fmt --check`,
`cargo check --all-targets`, `cargo clippy --all-targets -- -D warnings`
all PASS with zero warnings):**

- macOS: **441 Rust tests, 0 failed** (including the Ratatui
  `TestBackend` dashboard tests at 80×24 + resize); Python certification
  suite **62 OK**, scripts suite **79 OK**; loopback-mock HTTP tests
  cover the `Authorization: Bearer` header and the 401 mapping.
- Windows: **439 Rust tests, 0 failed** (the one-test delta vs macOS is
  the Unix-only key-file permission test, which does not compile on
  Windows — the expected platform delta); console `q` smoke PASS.
- Linux: **442 Rust tests, 0 failed** (the one-test delta vs macOS is
  the Linux-only multithreaded-discovery regression test: a single
  8-thread process resolves to exactly one discovery candidate); PTY
  `q` smoke PASS.
- Network tests use loopback mocks only; the pinned llama.cpp
  (`427291b`) and pinned model were used for the live run.

**M4 arm64 native verification (Apple M4 Max, macOS 26.6.2 arm64):**

- Shipped arm64 binary identity: the transferred binary's hash matched
  the staged record (`a8f8ab16…`), `file` → Mach-O arm64, minos 11.0.0,
  exactly the 5 system dylibs/frameworks, `codesign -dv` →
  `Signature=adhoc`, `ltop --version` → `ltop 0.1.2` (exit 0).
- Native PTY `q` smoke: PASS (clean exit, terminal restored).
- Loopback mock endpoint checks: **10/10 PASS** (real CPU% from
  time-differenced samples, non-zero RSS, the macOS N/A fields shown as
  N/A, remote-endpoint semantics).
- **Full 33-gate live certification: 33/33 gates PASS** (0 FAIL /
  0 SKIPPED / 0 N-A), finalized and not aborted, against a real
  llama-server (pinned commit, CPU-only static build, GPU off) with the
  pinned model, covering the live `/props`/`/slots`/`/metrics` schemas,
  the live-stream inference semantics, all TUI key/resize/restart/
  remote-semantics gates, terminal restoration on `q`/Ctrl-C, and the
  300 s soak.

**Windows ConPTY live certification: N/A with reason** — the live driver
is Unix/PTY-based; a Windows ConPTY live `llama-server` run is not
executable. Recorded N/A, never PASS (same status as the 0.1.0 Windows
artifact).

## Certification (0.1.1, sanitized summary)

The 0.1.1 artifacts were built and certified on 2026-09-06. This is the
durable sanitized summary; the machine-local reports are not published
(same policy as the 0.1.0 records: no internal host names, internal
IPs, machine-local paths, or report file names in this repository).

**Build (Intel macOS VM, macOS 26.6.2 x86_64):**

- Toolchain: rustc 1.98.0 (pinned via rustup, the 0.1.0 baseline
  compiler), targets `x86_64-apple-darwin` + `aarch64-apple-darwin`,
  Apple Command Line Tools SDK 26.5 (universal linker).
- Gates on the VM (host x86_64): `cargo fmt --check`,
  `cargo check --all-targets`, `cargo clippy --all-targets -- -D
  warnings`, `cargo test` — **384 tests, 0 failed**; Python suites
  `tests/cert` **62 OK**, `tests/scripts` **79 OK**; cross
  `cargo check --target aarch64-apple-darwin` PASS.
- arm64 cross-built with default `aarch64-apple-darwin` codegen (CPU
  `apple-m1`, the M1–M5 baseline; no `target-cpu`/`target-feature`
  overrides) and `MACOSX_DEPLOYMENT_TARGET=11.0`; x86_64 rebuilt at
  0.1.1 with the identical procedure. Build-home path remap + strip;
  the arm64 binary ad-hoc signed (kernel launch requirement), the
  x86_64 binary ad-hoc signed for consistency (post-sign re-verification:
  `--version`, PTY `q` smoke, linkage, machine-path scan — all PASS).

**Certification (Apple M4 Max, macOS 26.6.2 arm64):**

- Binary identity: transferred arm64 binary hash matched the build VM
  (`19a6e423…`), `file` → Mach-O arm64, minos 11.0.0, the 5 system
  dylibs, `Signature=adhoc`, `ltop --version` → `ltop 0.1.1`.
- Native gates on the M4: `cargo fmt --check`, `cargo check
  --all-targets`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test` — **384 tests, 0 failed** (native arm64 run of the full
  deterministic suite, including the Ratatui `TestBackend` dashboard
  tests); Python certification suite **62 OK**; real-PTY `q` smoke PASS.
- **Full 33-gate live certification: 33/33 gates PASS** (0 FAIL /
  0 SKIPPED / 0 N-A), against a real llama-server (pinned commit
  `427291b`, CPU-only static build, GPU off) with the pinned model
  (`Qwen3-4B-Q4_K_M.gguf`, 2,497,280,256 bytes, sha256
  `7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5` —
  hash matched), covering the live `/props`/`/slots`/`/metrics` schemas,
  the live-stream inference semantics, all TUI key/resize/restart/
  remote-semantics gates, terminal restoration on `q`/Ctrl-C, and a
  300 s soak (59 completions, no panic, RSS bounded 13,520 → 13,888 KiB,
  clean exit, no leftover processes).

**Homebrew cask (0.1.1):** definition-level checks (`brew style`,
`brew audit`, `brew info`) PASS on the Intel macOS VM (Homebrew 6.0.22);
per-architecture URL/checksum/binary resolution verified by stub-DSL
evaluation for both simulated architectures (and on the M4 itself); the
intel branch installed end-to-end from local assets (local server URL) on
the Intel VM before the v0.1.1 release was published — download,
SHA-256 verified by Homebrew, quarantine set, blocked quarantined first
run, recursive `xattr -dr` unblock, `ltop 0.1.1`, PTY `q` smoke, clean
uninstall with no residue. `brew livecheck` resolves the latest published
release (v0.1.1 now that the release is published). A full arm-branch
`brew install` on the M4 is **N/A** (Homebrew is not installed on that
non-admin machine); the arm64 *artifact* is fully
certified as above.

## Screenshot validation (genuine Terminal captures)

The dashboard screenshots in `assets/screenshots/` are **genuine screen
captures of ltop 0.1.0 running in macOS Terminal.app** — not synthetic
renderings. Capture setup (2026-09-06):

- **Terminal:** macOS Terminal.app 2.14 on the capture host. Temporary
  profiles were created for the capture (Menlo 13, opaque dark
  background, exact 80×24 and 120×40 grids, neutral custom title) and
  deleted afterwards; the host's existing Terminal windows and profiles
  were verified back to their original state after the capture (one
  pre-existing window was transiently re-profiled during setup and
  restored). The host's Terminal predates truecolor support, so
  ltop renders the Tokyo Night palette quantized to xterm-256 colors
  (background RGB 28,28,28, foreground 175,215,255, muted 95,95,135,
  primary 135,175,255, secondary 175,135,255).
- **Server data:** a Python stdlib mock llama-server bound to
  `127.0.0.1:8081` only (loopback; the host's real llama-server on port
  8080 was not touched) served stable mock `/metrics` and `/props`
  (model `qwen3-4b-q4_k_m.gguf`, context 32,768, 2 slots, build
  `b4923 (427291b)`) and dynamic `/slots` (slot 0 processing with its
  current-task token count advancing per poll), so ltop reached
  `connected` and displayed a live generation rate and live context
  usage. The mock's request log (steady 1 request/s per endpoint during
  each capture, with the captured frame bracketed by two consecutive
  samples) is the polling-cycle evidence.
- **Process metrics:** ltop was started with `--endpoint
  http://127.0.0.1:8081 --pid <worker>` where the worker is a controlled
  local `sleep` process. CPU, memory, PID and uptime in the images are
  **real capture-host measurements of that worker**; its ephemeral PID is
  shown as rendered (a measurement, not a secret), and macOS VIRT and
  thread count are N/A by design. No factual field was image-edited.
- **Capture:** each window was captured with `screencapture
  -l<windowID>` (the actual window ID) after at least two polling cycles,
  then cropped to the exact terminal content rectangle (title bar and
  desktop excluded) using measured grid geometry. No image editing of
  content was performed.

Validation performed:

| Check | Result |
|---|---|
| PNG signature, per-chunk CRCs, IHDR/IDAT/IEND order, 8-bit RGB, non-interlaced | PASS (2/2) |
| Dimensions: 1280×816 (80×24 char grid at 16×34 px/cell) and 1920×1360 (120×40) | PASS (2/2) |
| Grid geometry: panel border glyphs measured at exact cell centers (cell width 16.0 px, line height 34.0 px); content top/bottom span exactly 24/40 lines | PASS (2/2) |
| Cell-by-cell pixel ↔ text match against the terminal's own text buffer (read at the same instant): 1,910/1,910 checked cells (80×24) and 4,794/4,794 checked cells (120×40); the handful of cells whose digits advanced during the capture were exempted and are the only difference between the two text reads | PASS (2/2) |
| Palette: only the xterm-256-quantized Tokyo Night colors above (plus antialiasing blends of them) | PASS (2/2) |
| Content: `connected` status, all five panels (CPU/Memory/Inference/Slots/Server), live Slots/Inference values, full footer hints with right-pinned `@pauldckim` | PASS (2/2) |
| Privacy scan of the captured text: no hostnames, no machine-local paths, no non-loopback IPs, no port 8080; only `127.0.0.1:8081` and the worker's ephemeral PID (documented capture-host measurements) | PASS (2/2) |

Aesthetics were not assessed.
