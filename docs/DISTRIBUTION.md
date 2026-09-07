# Distribution & release process

This document describes how ltop releases are built, packaged, published
and (in the future) signed, and why the distribution channels are shaped
the way they are. It is the durable record for maintainers; users only need
[INSTALL.md](INSTALL.md) and [VERIFY.md](VERIFY.md).

## 1. Distribution model

- **Binary-only.** ltop is distributed as prebuilt binaries. The source
  code is not published and is not available from the distributor.
- **Repository role.** This repository
  (`pauldckim/ltop-release`) tracks **manifests, documentation,
  screenshots, license texts, SBOM and channel templates only**. The
  binaries themselves are **GitHub Release assets** — they are not tracked
  in git.
- **No Git LFS.** LFS is deliberately not used: the large files (binary
  archives) are release assets, not repo content, so there is nothing in
  the tracked tree that needs LFS. Text files use ordinary git.
- **Immutable releases.** Each version is a git tag (`vX.Y.Z`) with a
  GitHub Release attached. Published release assets are **never modified
  in place**; a changed artifact means a new version (or a new release
  with the old one superseded). Checksums are pinned per release in
  `releases/<version>/SHA256SUMS` (tracked) and in the release `SHA256SUMS`
  asset.

## 2. Why no native installers (0.1.0)

ltop is a **single self-contained CLI binary**: no installer database, no
services, no configuration files, no shared libraries to register, no
upgrade migration. The complete install is "extract → put on PATH"
([INSTALL.md](INSTALL.md)), and uninstall is "delete the file".

Native installer formats therefore add risk without adding capability:

| Format | Why it is not needed (yet) |
|---|---|
| macOS `.pkg` | A pkg would exist mainly to carry an Apple-signed/notarized payload and install hooks; ltop has neither. An unsigned pkg is strictly worse than a checksummed zip (Gatekeeper blocks it more aggressively). Revisit when Developer ID + notarization exist. |
| macOS `.dmg` | A DMG is a container for an `.app`/`.pkg`; for a CLI binary it is pure packaging overhead. |
| Windows `.msi` | An MSI adds registry entries and a Windows Installer database for a tool that needs neither; it also complicates silent/verified installs (the checksummed zip is simpler and fully silent). Revisit if a signed, registry-managed install is ever wanted. |
| Linux `.rpm`/`.deb` | Distro packaging implies a maintainer relationship, a repo, and per-distro ABI guarantees (glibc versions, etc.) that a single-binary release does not need; the tar.gz + PATH install works across distros. |

**Possible future channel needs** (re-evaluate per release):

- **macOS**: once binaries are Developer-ID signed + notarized, a `.pkg`
  (or just the zip) could be offered for convenience; a Homebrew cask
  (official or own tap) becomes viable (see §5).
- **Windows**: the portable ZIP route (`InstallerType: zip` +
  `NestedInstallerType: portable`) is supported by the WinGet schema and
  is the 0.1.0 plan (see §5); a signed silent installer (MSI or a signed
  EXE wrapper) remains the stronger route for AV/SmartScreen review (see
  §4).
- **Linux**: if aarch64 builds are added, the same tar.gz model extends
  unchanged; distro packages only if/when a community or vendor asks.

## 3. Release workflow (manual, current)

1. **Build** the release binaries on the target platforms from the final,
   gated source tree (build + full test gates must pass on each platform).
2. **Produce the final release binaries on each source platform**: rebuild
   from the same verified source with the build machine's home directory
   remapped to a neutral prefix
   (`RUSTFLAGS="--remap-path-prefix=<build-home>=/build"`, or
   `C:\build` on Windows) so no machine-local paths are embedded in panic
   or tracing metadata, and strip with the platform tool: macOS `strip`,
   Linux `strip --strip-all`, Windows cargo release output with
   `profile.release.strip=symbols` (via the
   `CARGO_PROFILE_RELEASE_STRIP` environment variable; the product source
   is not modified). Re-verify `--version` and run a PTY smoke test after
    stripping. The 0.1.0 binaries are unsigned, so stripping (which
    would invalidate a later signature) is applied before any signing
    step; signed releases must be signed after stripping. (0.1.1
    followed exactly this order: strip → ad-hoc sign → re-verify →
    final hash/scan; see §4.)
3. **Fetch** the stripped binaries into a local staging area (never into
   the tracked tree).
4. **Verify binary identity** — size and SHA-256 of each binary — *before*
   packaging. Any mismatch aborts the release.
5. **Package** each archive with a top-level directory
   `ltop-v<ver>-<target>/` containing exactly: the binary, `LICENSE.md`,
   `THIRD_PARTY_NOTICES.md`, `README.txt` (brief install/version/hash).
   Unix archives preserve the executable bit. Archives are produced
   deterministically (fixed timestamps, sorted entries, no machine-local
   metadata) so identical inputs yield identical bytes.
   `scripts/package-release.sh` implements this from prebuilt inputs and
   accepts the stripped binaries as-is (it verifies any input against the
   optional expected-sums file before packaging).
6. **Compute `SHA256SUMS`** over the archives; store a copy in
   `releases/v<ver>/SHA256SUMS` (tracked) and in `dist/v<ver>/` (local
   staging, gitignored).
7. **Verify the packages**: re-extract every archive, re-check binary
   hashes, run `ltop --version` and a PTY smoke test on the appropriate
   platform (native or VM), scan the binaries for machine-local paths
   (`strings`), and confirm the archive contains no source, no scripts,
   no private paths or hosts.
 8. **Publish**: create the `v<ver>` tag and the GitHub Release with the
    archives + `SHA256SUMS` as assets. Do not modify published assets.
 9. **Record**: update `CHANGELOG.md`, `docs/VERIFY.md` (real checksums +
    signature status) and the parent project's durable release record.

> **0.1.1 record (2026-09-06):** 0.1.1 is macOS-only — steps 1–7 were
> performed for `macos-arm64` (cross-built on the Intel macOS VM, rustc
> 1.98.0 pinned, default `aarch64-apple-darwin` codegen,
> `MACOSX_DEPLOYMENT_TARGET=11.0`) and `macos-x86_64` (rebuilt on the
> same VM) with the ad-hoc signing step of §4; the Windows and Linux
> 0.1.0 artifacts were not touched and remain the current release for
> those platforms. Step 8 (tag + GitHub Release) was **completed** on
> 2026-09-06: the `v0.1.1` tag and the
> [GitHub Release](https://github.com/pauldckim/ltop-release/releases/tag/v0.1.1)
> carry the two archives + `SHA256SUMS` (pinned in
> `releases/v0.1.1/SHA256SUMS`), and the cask/template/docs were updated.
> The packaging script
> (`scripts/package-release.sh`) gained `macos-arm64` support with
> target attributes derived from the target name (binary name, archive
> extension, platform line) instead of a hardcoded target list.

### 3.1 Public-safe helper scripts

The helpers in `scripts/` are public-safe: they contain no source code,
never read a source tree, and **never build, sign, tag, push, or
upload** — they only inspect local files (and, for `release-check.sh`,
local git metadata). All are POSIX sh and are covered by deterministic
shell tests under `scripts/tests/` (synthetic fixtures only; the tests
never touch the real release data):

```sh
sh scripts/tests/test-release-check.sh
sh scripts/tests/test-cask-update.sh
```

| Script | Purpose |
|---|---|
| `scripts/verify-release.sh` / `verify-release.ps1` | verify a `SHA256SUMS` file against local archives (macOS/Linux, Windows) |
| `scripts/package-release.sh` | package prebuilt binaries into deterministic release archives |
| `scripts/release-check.sh` | pre-publish gate: checksums, archive shape, cask mirror, SBOM, changelog, forbidden-content scan, tag state |
| `scripts/cask-update.sh` | generate the tap cask and the template mirror from one source (version, per-arch SHA-256, signing status) |

`release-check.sh` (exit 0 = all executed checks PASS, 1 = any FAIL,
2 = usage error):

```sh
sh scripts/release-check.sh <version> <dist_dir> <repo_root> \
    [cask_path] [component_count] [forbidden_patterns_file]
```

Checks: (1) every file listed in `releases/v<version>/SHA256SUMS`
exists in `<dist_dir>` with a matching SHA-256; (2) each archive has
exactly 4 files (`LICENSE.md`, `README.txt`,
`THIRD_PARTY_NOTICES.md`, the binary) under one top-level directory,
the binary is mode 755 on unix targets and carries no exec bit on
windows targets, and all entries share one timestamp; (3) with
`cask_path`, the `cask "ltop" do … end` region of
`homebrew/Casks/ltop.rb.template` is byte-identical to the live cask;
(4) `sbom/ltop-v<version>.cdx.json` parses as JSON with `specVersion`
1.6, `metadata.component.version` equal to `<version>`, and (with
`component_count`) the expected component count; (5) `CHANGELOG.md`
carries a `## <version> ` section; (6) no tracked file matches the
built-in forbidden patterns (machine-local path prefixes, VM directory
names, machine-local report/log file names, private-key material) nor
the EREs from `forbidden_patterns_file` (e.g. internal IP ranges —
passed as an argument, never committed here), and no tracked file name
carries a secret/signing extension; (7) the tag `v<version>` does not
exist yet (a published version is immutable, so the gate fails by
design when run against an already-tagged version).

`cask-update.sh` (exit 0 = generated + self-checked, 1 = self-check
failed, 2 = usage error):

```sh
sh scripts/cask-update.sh <version> <sha256_arm|-> <sha256_intel|-> \
    <signing: ad-hoc|unsigned|developer-id> <out_cask_path> <out_template_path>
```

Both outputs (the live tap cask and the `ltop.rb.template` reference
mirror) are written from the same generated body, so their
`cask "ltop" do … end` regions are byte-identical by construction; the
template additionally carries a generated header stating the version
and signing status. The per-release macOS signing status is an explicit
required input and the caveats are generated from it, so no stale
signing placeholder can survive in either file. Two-arch releases get
the `arch` stanza with per-arch `sha256` and `#{arch}` interpolation;
single-arch releases get a plain `sha256` with the architecture baked
into the `url`/`binary`. Self-checks: `ruby -c` on both outputs, region
diff, and a placeholder-token scan. The script never pushes the tap;
pushing the cask stays a separate, recorded step (after the GitHub
Release exists, so the cask URL resolves).

**WinGet helper: not implemented (deferred).** The Windows artifact is
not part of the current release cycle (0.1.1 is macOS-only; the 0.1.0
Windows asset is unchanged), so `winget-update.ps1` is not provided
yet. The manifest template in `winget/` remains manually maintained
until a Windows release needs it.

## 4. Signing (status and plan)

**Current (0.1.1): macOS ad-hoc signed; Windows/Linux (0.1.0) unsigned.**
The 0.1.1 macOS binaries are **ad-hoc signed** (`Signature=adhoc`): the
arm64 binary must carry at least an ad-hoc signature to launch on Apple
Silicon (a kernel requirement, not a trust requirement), and the x86_64
binary is ad-hoc signed for consistency with the arm64 artifact (the
0.1.0 x86_64 binary was unsigned; the 0.1.0 → 0.1.1 x86_64 delta is the
version string plus this signature). Ad-hoc signing is **not** a
Developer ID signature: neither binary passes Gatekeeper for quarantined
downloads, and the unblock procedure in [INSTALL.md](INSTALL.md) applies
unchanged. The 0.1.0 Windows binary remains unsigned (no Authenticode);
Linux uses checksums only. See [VERIFY.md](VERIFY.md) for what this means
per platform.

The F1 ordering (build → functional re-verify → strip → sign → final
hash/scan) was followed for 0.1.1: stripping invalidates signatures, so
signing was the last step and the shipped hashes are the post-signing
hashes; both binaries were functionally re-verified after signing
(`--version`, PTY `q` smoke, linkage, machine-path scan).

**Why self-signed certificates do not satisfy public trust:**

- *macOS*: Gatekeeper/notarization only accepts **Apple-issued Developer ID**
  signatures (paid Apple Developer Program) plus a notary ticket. A
  self-signed cert is rejected by Gatekeeper for ordinary users.
- *Windows*: public **SmartScreen** trust requires a CA-issued
  Authenticode certificate (DigiCert, Sectigo, GlobalSign, …) or
  Microsoft's Azure Artifact Signing / Store channels. A self-signed cert
  is only honored on machines where it was manually installed into the
  trusted store — developer or enterprise-managed environments.

So self-signed signing is a legitimate **integrity mechanism for
pre-trusted/local environments** (it proves the file is the one you
signed), but it does not make an unsigned-for-the-public package
"signed" in the Gatekeeper/SmartScreen sense.

**Plan (future releases):**

| Platform | Mechanism | Steps |
|---|---|---|
| macOS | Developer ID + notarization | Apple Developer Program → Developer ID Application certificate → `codesign --sign "Developer ID Application: …" --options runtime --timestamp ltop` → `xcrun notarytool submit --wait` → `xcrun stapler staple` → verify with `codesign -v --verbose=4` and `spctl --assess` |
| Windows | Authenticode | CA code-signing certificate (PFX) → `signtool sign /fd sha256 /tr <ts-rpc> /td sha256 /f cert.pfx ltop.exe` → `signtool verify /v` |
| Linux | GPG-signed checksums | `gpg --detach-sign SHA256SUMS` → publish `SHA256SUMS.sig` |

Signing material (certificates, keys, tokens) is **never committed** to
this repository (see `.gitignore`); it lives in the maintainer's secure
storage and is referenced only by name in release notes.

## 5. Package-manager channels

### Homebrew

- **`homebrew/core` formula: not possible.** Core formulas must build from
  DFSG-compatible open-source code; ltop is proprietary and binary-only.
- **Official `homebrew/cask`: blocked for 0.1.0/0.1.1.** A cask is the
  right *type* for proprietary binary-only software, but acceptance
  requires (a) macOS artifacts that pass Gatekeeper on a default
  configuration — i.e. **Developer ID signature + notarization** (an
  ad-hoc signature, as in 0.1.1, does not qualify) — (b) public presence
  / notability thresholds, and (c) maintainer discretion. None of these
  are met yet.
- **Own third-party tap: chosen route (live).** The tap
  `pauldckim/tap` (repository `pauldckim/homebrew-tap`) carries a cask
  that installs the macOS binary from this repository's GitHub Release.
  Since 0.1.1 the cask is **architecture-aware**: it declares
  `arch arm: "arm64", intel: "x86_64"` and per-architecture
  `sha256 arm: …, intel: …`, and the URL and binary path interpolate
  `#{arch}` (`ltop-v0.1.1-macos-<arch>.zip`), so the same one-line
  install works on Apple Silicon and Intel:
  `brew install --cask pauldckim/tap/ltop`. The 0.1.0 cask's
  `depends_on arch: :x86_64` requirement is removed; `depends_on
  macos: :big_sur` (11.0, the arm64 floor) is kept. Since Homebrew 6.0.0,
  non-official taps require explicit user trust: a fully-qualified
  install auto-taps the repository and trusts **only this cask**
  (cask-scoped entry in `~/.homebrew/trust.json`), not the whole tap.
  Because the 0.1.1 binaries are ad-hoc signed but **not**
  Developer-ID signed/notarized, the cask carries explicit first-run
  caveats (verify the per-architecture archive checksum, then remove the
  quarantine recursively with `xattr -dr` against
  `$(brew --prefix)/Caskroom/ltop` — architecture-independent — or use
  System Settings → Privacy & Security → "Open Anyway"); it does
  **not** remove the quarantine automatically, and the caveats state
  explicitly that ad-hoc signing is not a Developer ID signature.
  Developer ID + notarization remains the proper future fix (§4): once
  the artifacts pass Gatekeeper, the caveats become unnecessary and the
  official `homebrew/cask` route becomes realistic as well. The live
  cask (`Casks/ltop.rb` in the tap repository) is mirrored as a
  reference at `homebrew/Casks/ltop.rb.template` (deliberately **not** a
  `.rb` file, so `brew` will never load it); details in
  `homebrew/README.md`. Since 2026-09-07 both files are generated by
  `scripts/cask-update.sh` from one source (version, per-arch SHA-256,
  signing status), so the mirror cannot drift and no stale signing note
  can remain in the template header (§3.1).

### WinGet

- The official WinGet schema **supports portable ZIP packages**:
  `InstallerType: zip` with `NestedInstallerType: portable` and
  `NestedInstallerFiles` (`RelativeFilePath` + `PortableCommandAlias`) —
  see the current manifest schemas
  (<https://aka.ms/winget-manifest.singleton.1.12.0.schema.json>) and
  existing winget-pkgs packages (for example `Docker.DockerCLI`). A signed
  payload is **not** a schema requirement for this route.
- The template under `winget/manifests/` is a **future-ready singleton
  portable-ZIP manifest** (`.yaml.template`, deliberately not a `.yaml` so
  tooling never picks it up). It is validated against the official
  singleton schema v1.12.0 and carries the real v0.1.0 archive URL and the
  SHA-256 of the published `ltop-v0.1.0-windows-x86_64.zip` (pinned in
  `releases/v0.1.0/SHA256SUMS`).
- It is **not submittable as-is** for practical reasons, not schema
  reasons:
  1. the 0.1.0 Windows binary is unsigned; an unsigned portable exe may be
     flagged by AV/SmartScreen during review (see §4).
- **Route:** once the binary is signed (recommended before submission),
  Authenticode-signed), promote the template to
  `manifests/p/pauldckim/ltop/0.1.0/pauldckim.ltop.0.1.0.yaml` (or the
  multi-file `version`/`locale`/`installer` set) in a `microsoft/winget-pkgs`
  clone, re-verify the hash against the published asset, run
  `winget validate`, and open a pull request. Publisher `pauldckim`,
  package identifier `pauldckim.ltop`.

### Linux

Direct archive + checksums (this repository / GitHub Releases) is the
channel. The own-tap cask is macOS-only (arm64 + x86_64 since 0.1.1;
0.1.0 was x86_64 only via `depends_on arch: :x86_64`), so Linuxbrew
users keep using the archive route (the published 0.1.0 artifact);
distro repositories are out of scope.

## 6. What is (not) in a release

**In every archive:** binary, `LICENSE.md`, `THIRD_PARTY_NOTICES.md`,
`README.txt`. **As release assets additionally:** `SHA256SUMS`.

**Never in releases:** ltop source code, llama.cpp or model files, test or
build scripts, private documentation, logs, internal hostnames/IPs,
absolute machine paths, signing material. The shipped binaries are
stripped and built with the build home remapped to a neutral prefix, so
they embed no machine-local paths (verified by byte scan per release).
Screenshots are genuine Terminal.app captures taken against a
loopback-only mock llama-server endpoint (`127.0.0.1:8081`; mock model
name `qwen3-4b-q4_k_m.gguf`) with process metrics from a controlled local
worker process (real ephemeral PID; capture-host measurements — see
[VERIFY.md](VERIFY.md) "Screenshot validation").
