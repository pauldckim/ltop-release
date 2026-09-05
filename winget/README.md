# WinGet channel (template — NOT submittable as-is)

This directory contains a **disabled, future-ready template** for a WinGet
manifest for ltop.

## What the template is

`winget/manifests/p/pauldckim/ltop/0.1.0/pauldckim.ltop.0.1.0.yaml.template`
is a **singleton manifest** (all fields in one document) in the current
WinGet schema **v1.12.0**
(<https://aka.ms/winget-manifest.singleton.1.12.0.schema.json>), using the
official **portable-ZIP route**:

- `InstallerType: zip` — the archive is the installer;
- `NestedInstallerType: portable` — winget extracts it and runs the
  portable binary;
- `NestedInstallerFiles` — `RelativeFilePath`
  (`ltop-v0.1.0-windows-x86_64/ltop.exe`, relative to the zip root) plus
  `PortableCommandAlias: ltop`;
- `InstallerSha256` — the SHA-256 of the currently **staged**
  `ltop-v0.1.0-windows-x86_64.zip` (pinned in
  `releases/v0.1.0/SHA256SUMS`).

This route is fully supported by the official schema — it is used by
existing winget-pkgs packages (for example `Docker.DockerCLI`, which ships
multiple `NestedInstallerFiles` with aliases). The same fields can
equally be split into the multi-file `version`/`locale`/`installer`
manifest set per current winget-pkgs convention.

## Why the file is a template (`.yaml.template`), not a manifest

It is named `pauldckim.ltop.0.1.0.yaml.template` on purpose: winget
tooling and the `microsoft/winget-pkgs` validation pipeline only accept
`.yaml` manifests under `manifests/`, so this template can never be
accidentally submitted.

## Why it is not submittable today

None of the blockers below is a schema limitation — the schema accepts an
unsigned zip/portable manifest. They are practical/review blockers:

1. **The public release URL does not exist yet.** The repository and the
   `v0.1.0` GitHub Release (with the archive as an asset) are staged but
   not published, so `InstallerUrl` would 404. WinGet URL policy requires
   the `InstallerUrl` to come directly from the **publisher's release
   location** (third-party redirectors and vanity URLs are rejected as
   `Validation-Indirect-URL` / `Validation-Domain`). A GitHub Releases
   download URL under the publisher's own repository is the publisher's
   release location and is the standard route in winget-pkgs; GitHub's
   internal 302 from `releases/download/…` to its own asset CDN
   (`release-assets.githubusercontent.com`) is GitHub's delivery of the
   publisher's asset, not a third-party redirector.
2. **The 0.1.0 Windows binary is not Authenticode-signed.** An unsigned
   portable exe may be flagged by antivirus/SmartScreen during
   winget-pkgs review. A self-signed certificate does **not** satisfy
   public SmartScreen trust — public trust requires a CA-issued
   code-signing certificate (or Azure Artifact Signing / Store
   distribution). See
   [../docs/DISTRIBUTION.md](../docs/DISTRIBUTION.md) §4.
3. **Hash re-verification.** The template carries the staged archive
   hash; re-verify it against the published release asset before
   submission.

## Planned submission (future)

```
microsoft/winget-pkgs clone
  manifests/p/pauldckim/ltop/0.1.0/
    pauldckim.ltop.0.1.0.yaml     # promoted from this template
```

- `winget validate --manifest <file>` (schema check)
- pull request at <https://github.com/microsoft/winget-pkgs>
- publisher: `pauldckim` · package identifier: `pauldckim.ltop`

Microsoft may refuse submissions at its discretion; the manifest metadata
(`License` / `LicenseUrl`) carries the proprietary freeware terms.
