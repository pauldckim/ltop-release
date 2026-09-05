# Contributing

**ltop is developed by @pauldckim. This is a binary-only release
repository: the ltop source code is not published and is not available
from the distributor.**

## What this repository accepts

- **Packaging** — fixes to release archives, checksum manifests, install
  docs, and the Homebrew/WinGet channel templates.
- **Documentation** — corrections and clarifications in the README,
  `docs/`, `CHANGELOG.md`, `LICENSE.md` (typos/links), and
  `THIRD_PARTY_NOTICES.md`.
- **Issues** — bug reports, packaging problems, and feature requests via
  the issue tracker. Security issues go through the private vulnerability
  reporting channel (see [docs/SECURITY.md](docs/SECURITY.md)), never
  public issues.

## What this repository cannot accept

- **Source contributions.** ltop's source is not distributed; pull
  requests containing source code, source-level fixes, or source builds
  cannot be reviewed, merged or licensed here. If you have a bug or
  feature idea, open an issue describing the observed behavior (version,
  platform, endpoint, steps) and the maintainer will address it in the
  source project.
- **Modified binaries.** The license
  ([LICENSE.md](LICENSE.md)) prohibits modified/patched binaries and
  reverse engineering; redistributed binaries must be the unmodified
  release archives.

## How to propose changes

1. Fork the repository and open a pull request against `main`.
2. Keep changes minimal and limited to the accepted categories above.
3. Do not add binaries, LFS pointers, secrets or signing material; release
   artifacts live only in GitHub Release assets.
4. If you touch a checksum manifest or a channel template, verify it
   against the current release (see [docs/VERIFY.md](docs/VERIFY.md)).

The maintainer reviews and merges at their discretion; acceptance of a
change is not an endorsement of any license interpretation beyond
[LICENSE.md](LICENSE.md).
