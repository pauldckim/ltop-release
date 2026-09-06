# Homebrew channel (own tap — chosen route, live)

The **own tap** is the chosen Homebrew distribution route for ltop, and
it is live (tap repository published, cask at v0.1.1):

| Item | Value |
|---|---|
| Tap name | `pauldckim/tap` |
| Tap repository | [`pauldckim/homebrew-tap`](https://github.com/pauldckim/homebrew-tap) (published; `Casks/ltop.rb` at v0.1.1) |
| Live cask | `Casks/ltop.rb` in the tap repository |
| Install (one line) | `brew install --cask pauldckim/tap/ltop` |
| Platform | macOS arm64 + x86_64 (v0.1.1 ships both; the cask is architecture-aware via `arch arm: "arm64", intel: "x86_64"` and per-architecture `sha256 arm: …, intel: …`; the 0.1.0 `depends_on arch: :x86_64` requirement is removed) |
| Source of the binary | the official GitHub release in **this** repository (`pauldckim/ltop-release`), pinned by per-architecture SHA-256 |

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

## Ad-hoc signing limitation (0.1.1)

The v0.1.1 macOS binaries are **ad-hoc signed** — the arm64 binary must
carry at least an ad-hoc signature to launch on Apple Silicon (kernel
requirement), and the x86_64 binary is ad-hoc signed for consistency —
but they are **not** Developer-ID signed or notarized. Ad-hoc signing is
not a trust signal: Homebrew applies the quarantine attribute to the
download (and does not remove it), so the first run of a quarantined
binary is blocked by Gatekeeper exactly as with the unsigned 0.1.0
binary. The cask's `caveats` state this explicitly and print the exact
procedure: verify the per-architecture archive checksum, then either
remove the quarantine recursively
(`xattr -dr com.apple.quarantine "$(brew --prefix)/Caskroom/ltop"` —
architecture-independent) before the first run, or use **System
Settings → Privacy & Security → Open Anyway** after a blocked first run.

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
