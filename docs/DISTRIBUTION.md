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
   stripping. The binaries are unsigned at 0.1.0, so stripping (which
   would invalidate a later signature) is applied before any future
   signing step; signed future releases must be signed after stripping.
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

## 4. Signing (status and plan)

**Current (0.1.0): unsigned.** macOS and Windows binaries carry no code
signature; Linux uses checksums only. See [VERIFY.md](VERIFY.md) for what
this means per platform.

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
- **Official `homebrew/cask`: blocked for 0.1.0.** A cask is the right
  *type* for proprietary binary-only software, but acceptance requires
  (a) macOS artifacts that pass Gatekeeper on a default configuration —
  i.e. **Developer ID signature + notarization** — (b) public presence /
  notability thresholds, and (c) maintainer discretion. None of these are
  met yet. A template is kept at `homebrew/Casks/ltop.rb.template`
  (deliberately **not** a `.rb` file, so `brew` will never load it) with
  the activation blockers documented in `homebrew/README.md`.
- **Own third-party tap (future):** a `pauldckim/ltop-tap` repository with
  a cask is the realistic Homebrew route once the macOS binary is
  signed/notarized. Note: since Homebrew 6.0.0, non-official taps require
  explicit user trust (`brew trust`), and a tap cask still needs the
  Gatekeeper-passing artifact.

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
  SHA-256 of the staged `ltop-v0.1.0-windows-x86_64.zip` (pinned in
  `releases/v0.1.0/SHA256SUMS`).
- It is **not submittable as-is** for practical reasons, not schema
  reasons:
  1. the public release URL does not exist yet — the repository and the
     `v0.1.0` GitHub Release with the archive asset are staged but not
     published, so `InstallerUrl` would 404. WinGet URL policy requires the
     `InstallerUrl` to come **directly from the publisher's release
     location** (`Validation-Indirect-URL` / `Validation-Domain` reject
     third-party redirectors and vanity URLs). A GitHub Releases download
     URL under the publisher's own repository is the publisher's release
     location and is the standard route in winget-pkgs; GitHub serves the
     asset through an internal 302 to its own asset CDN
     (`release-assets.githubusercontent.com`), which is GitHub's delivery
     of the publisher's asset, not a third-party redirector, so the URL
     does not violate the policy;
  2. the 0.1.0 Windows binary is unsigned; an unsigned portable exe may be
     flagged by AV/SmartScreen during review (see §4).
- **Route:** once the release is published (and ideally the binary is
  Authenticode-signed), promote the template to
  `manifests/p/pauldckim/ltop/0.1.0/pauldckim.ltop.0.1.0.yaml` (or the
  multi-file `version`/`locale`/`installer` set) in a `microsoft/winget-pkgs`
  clone, re-verify the hash against the published asset, run
  `winget validate`, and open a pull request. Publisher `pauldckim`,
  package identifier `pauldckim.ltop`.

### Linux

Direct archive + checksums (this repository / GitHub Releases) is the
channel. Homebrew-on-Linux (Linuxbrew) users could use the future tap
cask; distro repositories are out of scope.

## 6. What is (not) in a release

**In every archive:** binary, `LICENSE.md`, `THIRD_PARTY_NOTICES.md`,
`README.txt`. **As release assets additionally:** `SHA256SUMS`.

**Never in releases:** ltop source code, llama.cpp or model files, test or
build scripts, private documentation, logs, internal hostnames/IPs,
absolute machine paths, signing material. The shipped binaries are
stripped and built with the build home remapped to a neutral prefix, so
they embed no machine-local paths (verified by byte scan per release).
Screenshots use mock data only (`http://localhost:8080`, mock PID, mock
model name).
