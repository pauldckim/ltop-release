# Homebrew channel (template — NOT active)

This directory contains a **disabled, future-ready template** for a Homebrew
cask that would install ltop from this repository's GitHub Releases.

## Why it is a template (`.rb.template`), not a cask

The file is named `ltop.rb.template` on purpose: Homebrew only loads
`Casks/*.rb`, so this template can never be accidentally installed or
audited as a live cask. It also contains explicit placeholders that would
fail `brew audit`/`brew style`.

**Activation blockers (all must be resolved before converting to
`Casks/ltop.rb` in a tap):**

1. **Signed + notarized macOS artifacts.** ltop 0.1.0 macOS binaries are
   **unsigned**. Homebrew applies quarantine to cask downloads and requires
   executable artifacts to **pass Gatekeeper on a default macOS
   configuration** — i.e. Developer ID signature + Apple notarization.
   Unsigned artifacts are not acceptable for an official cask and produce
   a broken first-run experience in a tap cask.
   Self-signed certificates do **not** satisfy this (see
   [../docs/DISTRIBUTION.md](../docs/DISTRIBUTION.md) §4).
2. **Real `sha256` values.** The template carries the placeholders
   `sha256 "REPLACE_WITH_REAL_SHA256_MACOS_ARM64"` and
   `sha256 "REPLACE_WITH_REAL_SHA256_MACOS_X86_64"` for the macOS arm64 and
   x86_64 archives (and `sha256 "REPLACE_WITH_REAL_SHA256_LINUX_X86_64"`
   for the Linux archive).
3. **Architecture coverage.** The template expects both `macos-arm64` and
   `macos-x86_64` artifacts; 0.1.0 ships x86_64 only.
4. **Notability / official cask (if pursuing `homebrew/cask`).** Official
   inclusion additionally requires public presence and notability
   thresholds (self-submission: 90 forks / 90 watchers / 225 stars, repo
   ≥ 30 days old) plus maintainer discretion. The realistic near-term
   route is an **own tap** (`pauldckim/ltop-tap`), where the acceptance
   policy does not apply but the Gatekeeper requirement still does.

## Planned tap structure (future)

```
pauldckim/ltop-tap/            # separate public git repository
  Casks/
    ltop.rb                    # promoted from this template
  README.md                    # tap description, trust instructions, license link
```

Planned user install (once activated):

```sh
brew tap pauldckim/ltop-tap
brew trust --cask pauldckim/ltop-tap/ltop   # required for non-official taps (Homebrew >= 6.0.0)
brew install --cask ltop
```

## Template contents

- `ltop.rb.template` — the cask definition with placeholders
  (`version`, per-arch `sha256`, `url` pointing at this repository's
  GitHub Releases, `binary` stanza, proprietary-license caveat).

Do not `brew install` anything from this directory.
