#!/bin/sh
# cask-update.sh — generate the ltop Homebrew cask from one source of
# truth: the live tap cask and the ltop-release template mirror are both
# written by this script from the same generated body, so the
# `cask "ltop" do ... end` region of the two files is byte-identical by
# construction (docs/010 §3 mirror rule, docs/013 §16.2).
#
# Public-safe: this script writes exactly the two files given as
# arguments and runs local self-checks (ruby -c, region diff,
# placeholder scan). It never builds, signs, tags, pushes, uploads, or
# touches the network. In particular it never pushes the tap.
#
# The per-release macOS signing status is an explicit required input;
# the caveats are generated from it, so no stale signing placeholder can
# survive in either output.
#
# POSIX sh. Requires: ruby (for the `ruby -c` self-check).
#
# Usage:
#   sh cask-update.sh <version> <sha256_arm|-> <sha256_intel|-> <signing> \
#       <out_cask_path> <out_template_path>
#
#   <version>            release version without leading v (e.g. 0.2.0)
#   <sha256_arm>         SHA-256 of ltop-v<version>-macos-arm64.zip, or -
#                        if the arm64 artifact is not shipped
#   <sha256_intel>       SHA-256 of ltop-v<version>-macos-x86_64.zip, or -
#                        if the x86_64 artifact is not shipped
#   <signing>            ad-hoc | unsigned | developer-id — the per-release
#                        macOS signing status (the caveats are generated
#                        from it)
#   <out_cask_path>      live tap cask to write, e.g. ../homebrew-tap/Casks/ltop.rb
#   <out_template_path>  reference mirror to write,
#                        ltop-release/homebrew/Casks/ltop.rb.template
#
# Two-arch releases get the `arch` stanza with per-arch `sha256` and
# `#{arch}` interpolation; single-arch releases get a plain `sha256`
# with the architecture baked into the url/binary (0.1.0 shape, modern
# livecheck).
#
# Exit codes: 0 = generated + self-checked, 1 = self-check failed,
#             2 = usage error.

set -u

if [ "$#" -ne 6 ]; then
    echo "usage: sh cask-update.sh <version> <sha256_arm|-> <sha256_intel|-> \\" >&2
    echo "       <signing: ad-hoc|unsigned|developer-id> <out_cask_path> <out_template_path>" >&2
    exit 2
fi

version=$1
sha_arm=$2
sha_intel=$3
signing=$4
out_cask=$5
out_template=$6

# --- input validation -------------------------------------------------------

if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: invalid version: $version" >&2
    exit 2
fi

is_sha() {
    [ "$1" = "-" ] || printf '%s' "$1" | grep -Eq '^[0-9a-fA-F]{64}$'
}
is_sha "$sha_arm" || { echo "error: sha256_arm must be 64 hex chars or -: $sha_arm" >&2; exit 2; }
is_sha "$sha_intel" || { echo "error: sha_intel must be 64 hex chars or -: $sha_intel" >&2; exit 2; }
if [ "$sha_arm" = "-" ] && [ "$sha_intel" = "-" ]; then
    echo "error: at least one architecture must be shipped" >&2
    exit 2
fi
case $signing in
    ad-hoc|unsigned|developer-id) : ;;
    *) echo "error: signing must be ad-hoc, unsigned, or developer-id: $signing" >&2; exit 2 ;;
esac
case $out_cask in */*) : ;; *) echo "error: out_cask_path must be a path: $out_cask" >&2; exit 2 ;; esac
case $out_template in */*) : ;; *) echo "error: out_template_path must be a path: $out_template" >&2; exit 2 ;; esac
cask_parent=$(dirname -- "$out_cask")
template_parent=$(dirname -- "$out_template")
[ -d "$cask_parent" ] || { echo "error: parent dir not found: $cask_parent" >&2; exit 2; }
[ -d "$template_parent" ] || { echo "error: parent dir not found: $template_parent" >&2; exit 2; }

if ! command -v ruby >/dev/null 2>&1; then
    echo "error: ruby is required for the self-check (ruby -c)" >&2
    exit 2
fi

workdir=$(mktemp -d "${TMPDIR:-/tmp}/ltop-cask-update.XXXXXX") || exit 2
trap 'rm -rf "$workdir"' EXIT INT TERM

# sha256 values are emitted lowercase.
sha_arm=$(printf '%s' "$sha_arm" | tr 'A-F' 'a-f')
sha_intel=$(printf '%s' "$sha_intel" | tr 'A-F' 'a-f')

# --- caveats (generated from the signing status) ----------------------------

# Common license paragraph.
caveats_license='    ltop is distributed under a proprietary freeware license (see
    https://github.com/pauldckim/ltop-release/blob/main/LICENSE.md): free
    to use and to redistribute unmodified; no sale, no modification, no
    reverse engineering. The source code is not published.'

if [ "$sha_arm" != "-" ] && [ "$sha_intel" != "-" ]; then
    glob="*--ltop-v$version-macos-*.zip"
    caveats_sha="      shasum -a 256 \"\$HOME/Library/Caches/Homebrew/downloads/\"$glob
      # expected (Apple Silicon / arm64):
      #   $sha_arm
      # expected (Intel / x86_64):
      #   $sha_intel"
else
    if [ "$sha_arm" != "-" ]; then
        single_sha=$sha_arm
        single_arch=arm64
    else
        single_sha=$sha_intel
        single_arch=x86_64
    fi
    caveats_sha="      shasum -a 256 \"\$HOME/Library/Caches/Homebrew/downloads/\"$single_sha--ltop-v$version-macos-$single_arch.zip
      # expected:
      #   $single_sha"
fi

caveats_unblock='    Then unblock the binary by either:

      1. removing the quarantine attribute recursively, before the
         first run:
         xattr -dr com.apple.quarantine "$(brew --prefix)/Caskroom/ltop"

      2. or running `ltop` once (it will be blocked), then opening
         System Settings > Privacy & Security and clicking "Open Anyway"
         next to the ltop warning

    If `ltop` was already run once and blocked, option 1 alone may not
    be enough (macOS caches the assessment per path); use option 2 or
    reboot in that case.'

caveats_footer='    Developer-ID signing + notarization is the proper fix and is
    planned; until then, treat this cask as a convenience channel, not
    an Apple-validated install.'

case $signing in
    ad-hoc)
        if [ "$sha_arm" != "-" ] && [ "$sha_intel" != "-" ]; then
            caveats_sign='    The v'"$version"' macOS binaries are ad-hoc signed: the arm64 binary must
    carry at least an ad-hoc signature to launch on Apple Silicon, and
    the x86_64 binary is ad-hoc signed for consistency. Ad-hoc signing
    is NOT a Developer ID signature — the binaries are not Developer-ID
    signed or notarized, and this cask does not remove the macOS
    quarantine attribute for you. The first run of `ltop` will be
    blocked by Gatekeeper.'
        elif [ "$sha_arm" != "-" ]; then
            caveats_sign='    The v'"$version"' macOS binary is ad-hoc signed: an arm64 binary must
    carry at least an ad-hoc signature to launch on Apple Silicon.
    Ad-hoc signing is NOT a Developer ID signature — the binary is not
    Developer-ID signed or notarized, and this cask does not remove the
    macOS quarantine attribute for you. The first run of `ltop` will be
    blocked by Gatekeeper.'
        else
            caveats_sign='    The v'"$version"' macOS binary is ad-hoc signed. Ad-hoc signing is NOT
    a Developer ID signature — the binary is not Developer-ID signed or
    notarized, and this cask does not remove the macOS quarantine
    attribute for you. The first run of `ltop` will be blocked by
    Gatekeeper.'
        fi
        caveats_body="$caveats_license

$caveats_sign

    Before unblocking it, verify the checksum of the downloaded archive
    (Homebrew already verified this SHA-256 during install; to re-check
    the cached download):

$caveats_sha

$caveats_unblock

$caveats_footer"
        ;;
    unsigned)
        if [ "$sha_arm" != "-" ] && [ "$sha_intel" != "-" ]; then
            caveats_sign='    The v'"$version"' macOS binaries are NOT signed and NOT notarized, and
    this cask does not remove the macOS quarantine attribute for you.
    The first run of `ltop` will be blocked by Gatekeeper.'
        else
            caveats_sign='    The v'"$version"' macOS binary is NOT signed and NOT notarized, and
    this cask does not remove the macOS quarantine attribute for you.
    The first run of `ltop` will be blocked by Gatekeeper.'
        fi
        caveats_body="$caveats_license

$caveats_sign

    Before unblocking it, verify the checksum of the downloaded archive
    (Homebrew already verified this SHA-256 during install; to re-check
    the cached download):

$caveats_sha

$caveats_unblock

$caveats_footer"
        ;;
    developer-id)
        if [ "$sha_arm" != "-" ] && [ "$sha_intel" != "-" ]; then
            caveats_sign='    The v'"$version"' macOS binaries are Developer-ID signed and
    notarized; Gatekeeper accepts them after the normal quarantine
    check, so no manual unblock procedure is needed.'
        else
            caveats_sign='    The v'"$version"' macOS binary is Developer-ID signed and
    notarized; Gatekeeper accepts it after the normal quarantine
    check, so no manual unblock procedure is needed.'
        fi
        caveats_body="$caveats_license

$caveats_sign

    To verify the checksum of the downloaded archive (Homebrew already
    verified this SHA-256 during install; to re-check the cached
    download):

$caveats_sha"
        ;;
esac

# --- cask body ---------------------------------------------------------------

if [ "$sha_arm" != "-" ] && [ "$sha_intel" != "-" ]; then
    {
        printf '%s\n' 'cask "ltop" do'
        printf '%s\n' '  arch arm: "arm64", intel: "x86_64"'
        printf '%s\n' ''
        printf '  version "%s"\n' "$version"
        printf '  sha256 arm:   "%s",\n' "$sha_arm"
        printf '         intel: "%s"\n' "$sha_intel"
        printf '%s\n' ''
        printf '  url "https://github.com/pauldckim/ltop-release/releases/download/v#{version}/ltop-v#{version}-macos-#{arch}.zip"\n'
        printf '%s\n' '  name "ltop"'
        printf '%s\n' '  desc "Single-binary TUI monitor for llama.cpp llama-server and its local process"'
        printf '%s\n' '  homepage "https://github.com/pauldckim/ltop-release"'
        printf '%s\n' ''
        printf '%s\n' '  livecheck do'
        printf '%s\n' '    url "https://github.com/pauldckim/ltop-release/releases/latest"'
        printf '%s\n' '    strategy :github_latest'
        printf '%s\n' '  end'
        printf '%s\n' ''
        printf '  # %s ships both Apple architectures, so the 0.1.0\n' "$version"
        printf '%s\n' '  # `depends_on arch: :x86_64` is removed. 11.0 (Big Sur) is the'
        printf '%s\n' '  # arm64 macOS floor and the oldest macOS Homebrew 6 can express.'
        printf '%s\n' '  depends_on macos: :big_sur'
        printf '%s\n' ''
        printf '%s\n' '  # The release archive contains a single top-level directory with'
        printf '%s\n' '  # the binary nested inside; reference it by that path.'
        printf '  binary "ltop-v#{version}-macos-#{arch}/ltop"\n'
        printf '%s\n' ''
        printf '%s\n' '  caveats <<~EOS'
        printf '%s\n' "$caveats_body"
        printf '%s\n' '  EOS'
        printf '%s\n' ''
        printf '%s\n' '  # No `uninstall` stanza: the `binary` stanza creates a symlink in'
        printf '%s\n' '  # Homebrew'"'"'s bin directory, and Homebrew removes that symlink'
        printf '%s\n' '  # automatically on `brew uninstall --cask ltop`. ltop installs nothing'
        printf '%s\n' '  # else (no app bundle, no support files), so there is nothing left to'
        printf '%s\n' '  # trash.'
        printf '%s\n' 'end'
    } > "$workdir/cask.rb"
elif [ "$sha_arm" != "-" ]; then
    {
        printf '%s\n' 'cask "ltop" do'
        printf '  version "%s"\n' "$version"
        printf '  sha256 "%s"\n' "$sha_arm"
        printf '%s\n' ''
        printf '  url "https://github.com/pauldckim/ltop-release/releases/download/v#{version}/ltop-v#{version}-macos-arm64.zip"\n'
        printf '%s\n' '  name "ltop"'
        printf '%s\n' '  desc "Single-binary TUI monitor for llama.cpp llama-server and its local process"'
        printf '%s\n' '  homepage "https://github.com/pauldckim/ltop-release"'
        printf '%s\n' ''
        printf '%s\n' '  livecheck do'
        printf '%s\n' '    url "https://github.com/pauldckim/ltop-release/releases/latest"'
        printf '%s\n' '    strategy :github_latest'
        printf '%s\n' '  end'
        printf '%s\n' ''
        printf '  # %s ships the Apple Silicon (arm64) macOS artifact only.\n' "$version"
        printf '%s\n' '  # 11.0 (Big Sur) is the arm64 macOS floor.'
        printf '%s\n' '  depends_on macos: :big_sur'
        printf '%s\n' ''
        printf '%s\n' '  # The release archive contains a single top-level directory with'
        printf '%s\n' '  # the binary nested inside; reference it by that path.'
        printf '  binary "ltop-v#{version}-macos-arm64/ltop"\n'
        printf '%s\n' ''
        printf '%s\n' '  caveats <<~EOS'
        printf '%s\n' "$caveats_body"
        printf '%s\n' '  EOS'
        printf '%s\n' ''
        printf '%s\n' '  # No `uninstall` stanza: the `binary` stanza creates a symlink in'
        printf '%s\n' '  # Homebrew'"'"'s bin directory, and Homebrew removes that symlink'
        printf '%s\n' '  # automatically on `brew uninstall --cask ltop`. ltop installs nothing'
        printf '%s\n' '  # else (no app bundle, no support files), so there is nothing left to'
        printf '%s\n' '  # trash.'
        printf '%s\n' 'end'
    } > "$workdir/cask.rb"
else
    {
        printf '%s\n' 'cask "ltop" do'
        printf '  version "%s"\n' "$version"
        printf '  sha256 "%s"\n' "$sha_intel"
        printf '%s\n' ''
        printf '  url "https://github.com/pauldckim/ltop-release/releases/download/v#{version}/ltop-v#{version}-macos-x86_64.zip"\n'
        printf '%s\n' '  name "ltop"'
        printf '%s\n' '  desc "Single-binary TUI monitor for llama.cpp llama-server and its local process"'
        printf '%s\n' '  homepage "https://github.com/pauldckim/ltop-release"'
        printf '%s\n' ''
        printf '%s\n' '  livecheck do'
        printf '%s\n' '    url "https://github.com/pauldckim/ltop-release/releases/latest"'
        printf '%s\n' '    strategy :github_latest'
        printf '%s\n' '  end'
        printf '%s\n' ''
        printf '  # %s ships the Intel (x86_64) macOS artifact only.\n' "$version"
        printf '%s\n' '  depends_on arch: :x86_64'
        printf '%s\n' '  depends_on macos: :big_sur'
        printf '%s\n' ''
        printf '%s\n' '  # The release archive contains a single top-level directory with'
        printf '%s\n' '  # the binary nested inside; reference it by that path.'
        printf '  binary "ltop-v#{version}-macos-x86_64/ltop"\n'
        printf '%s\n' ''
        printf '%s\n' '  caveats <<~EOS'
        printf '%s\n' "$caveats_body"
        printf '%s\n' '  EOS'
        printf '%s\n' ''
        printf '%s\n' '  # No `uninstall` stanza: the `binary` stanza creates a symlink in'
        printf '%s\n' '  # Homebrew'"'"'s bin directory, and Homebrew removes that symlink'
        printf '%s\n' '  # automatically on `brew uninstall --cask ltop`. ltop installs nothing'
        printf '%s\n' '  # else (no app bundle, no support files), so there is nothing left to'
        printf '%s\n' '  # trash.'
        printf '%s\n' 'end'
    } > "$workdir/cask.rb"
fi

# --- template mirror (generated header + same body) --------------------------

{
    printf '%s\n' '# ==========================================================================='
    printf '%s\n' '# ltop Homebrew cask — REFERENCE COPY (not a live cask)'
    printf '%s\n' '#'
    printf '%s\n' '# This file is intentionally named `ltop.rb.template` (not `ltop.rb`) so'
    printf '%s\n' '# that Homebrew never loads it. It is kept as a byte-level mirror of the'
    printf '%s\n' '# live cask in the own tap:'
    printf '%s\n' '#'
    printf '%s\n' '#   live copy:  https://github.com/pauldckim/homebrew-tap'
    printf '%s\n' '#               (Casks/ltop.rb — tap name `pauldckim/tap`)'
    printf '%s\n' '#'
    printf '%s\n' '# The own tap is the chosen and live Homebrew route (see ../README.md).'
    printf '%s\n' '# When the live cask changes (version bump, signing status, caveats),'
    printf '%s\n' '# this reference copy must be updated to match.'
    printf '%s\n' '#'
    printf '# Generated by scripts/cask-update.sh for version %s (signing: %s).\n' "$version" "$signing"
    printf '%s\n' '# The `cask "ltop" do ... end` region below is byte-identical to the'
    printf '%s\n' '# live cask (the generator verifies this with a self-check).'
    printf '%s\n' '# ==========================================================================='
    printf '%s\n' ''
    cat "$workdir/cask.rb"
} > "$workdir/template.rb"

# --- write the outputs --------------------------------------------------------

cp "$workdir/cask.rb" "$out_cask" || { echo "error: cannot write $out_cask" >&2; exit 1; }
cp "$workdir/template.rb" "$out_template" || { echo "error: cannot write $out_template" >&2; exit 1; }

# --- self-checks ---------------------------------------------------------------

status=0

ruby -c "$out_cask" >/dev/null 2>&1 || { echo "FAIL self-check: ruby -c on $out_cask"; status=1; }
ruby -c "$out_template" >/dev/null 2>&1 || { echo "FAIL self-check: ruby -c on $out_template"; status=1; }

sed -n '/^cask "ltop" do$/,/^end$/p' "$out_cask" > "$workdir/region.cask"
sed -n '/^cask "ltop" do$/,/^end$/p' "$out_template" > "$workdir/region.template"
if cmp -s "$workdir/region.cask" "$workdir/region.template"; then
    echo "PASS self-check: cask region byte-identical between $out_cask and $out_template"
else
    echo "FAIL self-check: cask region differs between the two outputs"
    status=1
fi

# No placeholder or stale-signing token may survive in either output.
if grep -nE 'REPLACE|PLACEHOLDER|TODO|XXX|<sha|<version|FIXME' "$out_cask" "$out_template" >/dev/null 2>&1; then
    echo "FAIL self-check: placeholder token found in the output"
    grep -nE 'REPLACE|PLACEHOLDER|TODO|XXX|<sha|<version|FIXME' "$out_cask" "$out_template" | sed 's/^/    /'
    status=1
else
    echo "PASS self-check: no placeholder tokens in the output"
fi

if [ "$status" -ne 0 ]; then
    echo "cask-update: self-check FAILED (outputs were written; fix and re-run)" >&2
    exit 1
fi

echo "cask-update: wrote $out_cask and $out_template (version $version, signing $signing)"
exit 0
