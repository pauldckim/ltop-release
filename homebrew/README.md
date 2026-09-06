# Homebrew channel (own tap — chosen route, preparation complete)

The **own tap** is the chosen Homebrew distribution route for ltop, and
its preparation is complete:

| Item | Value |
|---|---|
| Tap name | `pauldckim/tap` |
| Tap repository | [`pauldckim/homebrew-tap`](https://github.com/pauldckim/homebrew-tap) (staged locally at `../homebrew-tap/` in the parent project) |
| Live cask | `Casks/ltop.rb` in the tap repository |
| Install (one line) | `brew install --cask pauldckim/tap/ltop` |
| Platform | macOS x86_64 only (v0.1.0 ships a macOS x86_64 binary; `depends_on arch: :x86_64`) |
| Source of the binary | the official GitHub release in **this** repository (`pauldckim/ltop-release`), pinned by SHA-256 |

## How the one-line install works (Homebrew ≥ 6)

`brew install --cask pauldckim/tap/ltop` does everything:

1. **Auto-tap.** The fully-qualified cask name makes Homebrew tap
   `pauldckim/tap` automatically (cloning
   `https://github.com/pauldckim/homebrew-tap`) if it is not tapped yet.
   No separate `brew tap` step is needed.
2. **Scoped trust.** Since Homebrew 6, non-official taps must be
   explicitly trusted before their casks are loaded. A fully-qualified
   install trusts **only this cask** (`pauldckim/tap/ltop`), recorded in
   `~/.homebrew/trust.json` — it does not blanket-trust the whole tap.
   Installing by the bare name instead (`brew install --cask ltop`)
   requires `brew trust --cask pauldckim/tap/ltop` first.
3. **Official source only.** The cask is declarative: Homebrew downloads
   the release archive from this repository's GitHub Release and
   verifies its SHA-256. The tap repository contains no binaries and no
   install scripts — nothing is copied out of the tap and executed
   locally.

## Unsigned limitation (0.1.0)

The v0.1.0 macOS binary is **not** Developer-ID signed or notarized.
The cask installs it anyway as a **convenience channel**: Homebrew
applies the quarantine attribute to the download (and does not remove
it), so the first run is blocked by Gatekeeper. The cask's `caveats`
print the exact procedure: verify the archive checksum, then either
remove the quarantine recursively
(`xattr -dr com.apple.quarantine /usr/local/Caskroom/ltop`) before the
first run, or use **System Settings → Privacy & Security → Open
Anyway** after a blocked first run.

**Developer-ID signing + notarization remains the proper future fix**
(see [../docs/DISTRIBUTION.md](../docs/DISTRIBUTION.md) §4): once the
macOS artifacts are signed and notarized, the first-run caveats become
unnecessary, and submission to the official `homebrew/cask`
additionally becomes realistic (notability thresholds apply there; they
do not for an own tap).

## Reference template

- `Casks/ltop.rb.template` — a **reference copy** of the live cask. It
  is named `.template` (not `.rb`) so Homebrew never loads it from this
  repository; the live copy is `Casks/ltop.rb` in the
  `pauldckim/homebrew-tap` tap repository. Keep the two in sync when the
  cask changes.

Do not `brew install` anything from this directory.
