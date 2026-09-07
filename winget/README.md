# WinGet channel (template — NOT submittable as-is)

This directory contains **disabled, future-ready templates** for WinGet
manifests for ltop.

## What the templates are

- `winget/manifests/p/pauldckim/ltop/0.1.0/pauldckim.ltop.0.1.0.yaml.template`
  is a **singleton manifest** (all fields in one document) in the WinGet
  schema **v1.12.0**
  (<https://aka.ms/winget-manifest.singleton.1.12.0.schema.json>), using
  the official **portable-ZIP route** (recorded for the 0.1.0 Windows
  artifact; the 0.1.0 asset remains the published 0.1.0 release).
- `winget/manifests/p/pauldckim/ltop/0.1.2/` is the **0.1.2 multi-file
  manifest set** (current winget-pkgs convention: version-less file names
  under the version directory, the en-US file using the `locale.` infix
  and `ManifestType: defaultLocale`):
  - `pauldckim.ltop.yaml.template` — version manifest
    (<https://aka.ms/winget-manifest.version.1.12.0.schema.json>);
  - `pauldckim.ltop.locale.en-US.yaml.template` — default-locale manifest
    (<https://aka.ms/winget-manifest.defaultLocale.1.12.0.schema.json>);
  - `pauldckim.ltop.installer.yaml.template` — installer manifest
    (<https://aka.ms/winget-manifest.installer.1.12.0.schema.json>).

The 0.1.2 set uses the same official **portable-ZIP route**:

- `InstallerType: zip` — the archive is the installer;
- `NestedInstallerType: portable` — winget extracts it and runs the
  portable binary;
- `NestedInstallerFiles` — `RelativeFilePath`
  (`ltop-v0.1.2-windows-x86_64/ltop.exe`, relative to the zip root) plus
  `PortableCommandAlias: ltop`;
- `InstallerSha256` — the SHA-256 of the **staged**
  `ltop-v0.1.2-windows-x86_64.zip` (pinned in
  `releases/v0.1.2/SHA256SUMS`); `InstallerUrl` is the scheduled v0.1.2
  GitHub Release asset URL (it resolves once the release is published).
- No `Scope` on the installer entry: winget reports "Scope is not
  supported for InstallerType portable", so the field is omitted
  (warning-free validation).

This route is fully supported by the official schema — it is used by
existing winget-pkgs packages (for example `Docker.DockerCLI`, which ships
multiple `NestedInstallerFiles` with aliases). The 0.1.2 set was
generated from the 0.1.0 singleton template with the version, the
scheduled asset URL and the staged archive hash substituted, and
`winget validate` passed on it (Windows host, winget v1.29.290,
2026-09-08: "Manifest validation succeeded", no warnings).

## Why the files are templates (`.yaml.template`), not manifests

They are named `pauldckim.ltop.0.1.0.yaml.template` and
`pauldckim.ltop.{,locale.en-US.,installer.}yaml.template` on purpose:
winget tooling and the `microsoft/winget-pkgs` validation pipeline only
accept `.yaml` manifests under `manifests/`, so the templates can never be
accidentally submitted.

## Why the 0.1.2 set is not submittable today

None of the blockers below is a schema limitation — the schema accepts an
unsigned zip/portable manifest. They are practical/review blockers:

1. **The v0.1.2 GitHub Release does not exist yet.** The `InstallerUrl`
   (the scheduled v0.1.2 asset URL) would 404 until the release is
   published. WinGet URL policy requires the `InstallerUrl` to come
   directly from the **publisher's release location** (third-party
   redirectors and vanity URLs are rejected as
   `Validation-Indirect-URL` / `Validation-Domain`). A GitHub Releases
   download URL under the publisher's own repository is the publisher's
   release location and is the standard route in winget-pkgs; GitHub's
   internal 302 from `releases/download/…` to its own asset CDN
   (`release-assets.githubusercontent.com`) is GitHub's delivery of the
   publisher's asset, not a third-party redirector.
2. **The 0.1.2 Windows binary is not Authenticode-signed** (same status
   as 0.1.0). An unsigned portable exe may be flagged by
   antivirus/SmartScreen during winget-pkgs review. A self-signed
   certificate does **not** satisfy public SmartScreen trust — public
   trust requires a CA-issued code-signing certificate (or Azure Artifact
   Signing / Store distribution). See
   [../docs/DISTRIBUTION.md](../docs/DISTRIBUTION.md) §4.
3. **Hash re-verification.** The template carries the staged archive
   hash; re-verify it against the published release asset before
   submission.

(The 0.1.0 singleton template remains the record for the published 0.1.0
Windows artifact; its blockers were the same with the 0.1.0 URL/hash.)

## Planned submission (future)

```
microsoft/winget-pkgs clone
  manifests/p/pauldckim/ltop/0.1.2/
    pauldckim.ltop.yaml                  # promoted from the version template
    pauldckim.ltop.locale.en-US.yaml     # promoted from the locale template
    pauldckim.ltop.installer.yaml        # promoted from the installer template
```

- `winget validate --manifest <dir>` (schema check; passed on the staged
  set, 2026-09-08)
- pull request at <https://github.com/microsoft/winget-pkgs>
- publisher: `pauldckim` · package identifier: `pauldckim.ltop`

Microsoft may refuse submissions at its discretion; the manifest metadata
(`License` / `LicenseUrl`) carries the proprietary freeware terms.
