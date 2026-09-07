#!/bin/sh
# ltop installer — macOS (arm64 / x86_64) and Linux (x86_64). POSIX sh.
#
# Tag-pinned one-line install:
#
#   curl --proto '=https' --tlsv1.2 -fsSL \
#     https://raw.githubusercontent.com/pauldckim/ltop-release/install-v1/install.sh | sh
#
# What it does
#   - detects the platform (macOS arm64/x86_64, Rosetta-aware; Linux x86_64)
#   - downloads the pinned release archive over HTTPS (TLS >= 1.2) only
#   - verifies four embedded SHA-256 values before anything is installed:
#       1. the archive (mandatory)
#       2. the release SHA256SUMS file (downloaded and hash-checked)
#       3. the archive line inside that SHA256SUMS (cross-check)
#       4. the extracted binary
#   - installs atomically: temp file in the target directory + chmod 0755 + mv
#   - default target: $HOME/.local/bin/ltop (no sudo, no shell rc changes,
#     no services, no state)
#
# Safety behavior
#   - an existing file at the target that is the expected binary: no-op
#     (idempotent, exit 0)
#   - an existing file that is not the expected binary (older ltop or a
#     foreign file): refused in non-interactive mode unless --force;
#     interactive mode asks before replacing. A symlink at the target is
#     never followed or overwritten without explicit consent; with consent
#     only the link itself is removed.
#   - --uninstall removes the target only when its hash matches a known
#     ltop binary (all 0.1.0/0.1.1 macOS/Linux hashes); foreign files are
#     refused.
#   - unsafe prefixes (filesystem root, core system directories) are
#     rejected; the installer never escalates privileges.
#   - macOS: the installer never removes the com.apple.quarantine
#     attribute. If the installed binary carries it, it prints
#     checksum-first / System Settings guidance instead.
#   - downloads are HTTPS-only; redirect targets are restricted to the
#     base URL's host (test mode) or the GitHub release hosts (production).
#
# Test-only environment hooks (documented so production defaults cannot be
# weakened inadvertently; the hash pipeline is enforced in all modes, so a
# base-URL override alone cannot substitute different artifacts):
#   LTOP_RELEASE_BASE_URL   alternate download base, default:
#                           https://github.com/pauldckim/ltop-release/releases/download
#   LTOP_INSTALL_PLATFORM   bypass detection: macos-arm64 | macos-x86_64 |
#                           linux-x86_64
#   LTOP_INSTALL_INTERACTIVE=1
#                           force the interactive prompt path (default:
#                           prompt only when stdin is a terminal)
#   LTOP_INSTALL_TEST_MANIFEST
#                           path to a manifest file replacing the embedded
#                           platform mapping (used by scripts/tests/
#                           test-install.sh with synthetic fixtures). One
#                           line per platform:
#                             <platform> <version> <archive> <archive_sha256>
#                             <binary_sha256> <sums_sha256> <kind>
#                           The first line per platform key wins. All
#                           manifest binary hashes join the known-ltop set
#                           used by --uninstall and the existing-file
#                           message. Never set in production.
#
# Exit codes: 0 = installed / already installed / uninstalled / dry-run ok
#             1 = runtime failure (hash mismatch, download failure,
#                 refused replacement, unsupported platform, ...)
#             2 = usage error
#
# License: ltop is proprietary freeware. By installing you accept the
# license at https://github.com/pauldckim/ltop-release/blob/main/LICENSE.md
# (the full text ships inside every release archive as LICENSE.md).

set -u

INSTALLER_CHANNEL='install-v1'
REPO_URL='https://github.com/pauldckim/ltop-release'
LICENSE_URL='https://github.com/pauldckim/ltop-release/blob/main/LICENSE.md'
DEFAULT_BASE_URL='https://github.com/pauldckim/ltop-release/releases/download'
# final-URL hosts allowed in production mode (GitHub release download chain;
# GitHub has rotated the asset CDN host over time — objects.* is the legacy
# host, release-assets.* the current one)
PROD_ALLOWED_HOSTS='github.com objects.githubusercontent.com release-assets.githubusercontent.com raw.githubusercontent.com codeload.github.com'

# ---------------------------------------------------------------------------
# Pinned platform mapping.
#
# Values are the published, immutable release artifacts (release-repo
# releases/v0.1.0/SHA256SUMS, releases/v0.1.1/SHA256SUMS, docs/VERIFY.md):
#
#   platform      version  archive                          kind
#   macos-arm64   0.1.1    ltop-v0.1.1-macos-arm64.zip      zip
#   macos-x86_64  0.1.1    ltop-v0.1.1-macos-x86_64.zip     zip
#   linux-x86_64  0.1.0    ltop-v0.1.0-linux-x86_64.tar.gz  targz
#
# 0.1.1 is macOS-only; the published 0.1.0 Linux artifact remains the
# current Linux release.
# ---------------------------------------------------------------------------

platform_version() {
    case "$1" in
        macos-arm64)   printf '0.1.1' ;;
        macos-x86_64)  printf '0.1.1' ;;
        linux-x86_64)  printf '0.1.0' ;;
        *)             return 1 ;;
    esac
}

platform_archive() {
    case "$1" in
        macos-arm64)   printf 'ltop-v0.1.1-macos-arm64.zip' ;;
        macos-x86_64)  printf 'ltop-v0.1.1-macos-x86_64.zip' ;;
        linux-x86_64)  printf 'ltop-v0.1.0-linux-x86_64.tar.gz' ;;
        *)             return 1 ;;
    esac
}

platform_archive_sha() {
    case "$1" in
        macos-arm64)   printf '66c97f41f4a0c9919b89f8a003366a36f8e77d79af03ec866dccb3efbaa9fa55' ;;
        macos-x86_64)  printf '676da4356e00813e35092c8f386daa78ee41cca09a8f033949ca452135e5bdd9' ;;
        linux-x86_64)  printf 'f940cf94a1023f4764a82f8e4bda5c075a09f1407baccaeeb4527574ad3f8722' ;;
        *)             return 1 ;;
    esac
}

platform_binary_sha() {
    case "$1" in
        macos-arm64)   printf '19a6e42346f05dc37dd00f9ff723408d870237b72dc7a9cd77245069f443401a' ;;
        macos-x86_64)  printf '00933d50ef9ca133d788f0a1d883f1ab71dd0acacfc6cf9eb0c2b89c4fba6cbd' ;;
        linux-x86_64)  printf 'e18a3f0e9ea2e61ec5a44d5ab54256b774aec83a7d2ab4cf9e2f0df91daff089' ;;
        *)             return 1 ;;
    esac
}

# SHA-256 of the published SHA256SUMS release asset for the platform's
# version (v0.1.1 asset is shared by both macOS platforms).
platform_sums_sha() {
    case "$1" in
        macos-arm64|macos-x86_64)
            printf '79568789220e644d690bb1ef6c4091f126053a9a8f9670f4046f20775d4e6e12' ;;
        linux-x86_64)
            printf '6d5a9a753cdc272cf9284fa8b9ed3ea13f12028847804c3be4e66f01e910821c' ;;
        *) return 1 ;;
    esac
}

platform_kind() {
    case "$1" in
        macos-arm64|macos-x86_64) printf 'zip' ;;
        linux-x86_64)             printf 'targz' ;;
        *)                        return 1 ;;
    esac
}

# Every known ltop binary hash (0.1.0 + 0.1.1, macOS + Linux). Used for the
# "this looks like an older ltop" message and for --uninstall.
_known_ltop_hash_builtin() {
    case "$1" in
        19a6e42346f05dc37dd00f9ff723408d870237b72dc7a9cd77245069f443401a)
            printf 'ltop v0.1.1 macos-arm64' ;;
        00933d50ef9ca133d788f0a1d883f1ab71dd0acacfc6cf9eb0c2b89c4fba6cbd)
            printf 'ltop v0.1.1 macos-x86_64' ;;
        e18a3f0e9ea2e61ec5a44d5ab54256b774aec83a7d2ab4cf9e2f0df91daff089)
            printf 'ltop v0.1.0 linux-x86_64' ;;
        9e67b47cdfeb7448bdaec8e265e5494e4b8dbdf5c30257d8c85e974ebc068ebd)
            printf 'ltop v0.1.0 macos-x86_64' ;;
        *)
            return 1 ;;
    esac
}

# Describe a known ltop binary hash (embedded set +, in test mode, the
# manifest set). Prints a description; returns 1 if unknown.
describe_known_hash() {
    if desc=$(_known_ltop_hash_builtin "$1"); then
        printf '%s\n' "$desc"
        return 0
    fi
    if [ -n "$MANIFEST_FILE" ]; then
        mline=$(awk -v h="$1" '$5 == h {print; exit}' "$MANIFEST_FILE")
        if [ -n "$mline" ]; then
            mplat=${mline%% *}
            mrest=${mline#* }
            mver=${mrest%% *}
            printf 'ltop v%s %s (test manifest)\n' "$mver" "$mplat"
            return 0
        fi
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

QUIET=0
info() {
    [ "$QUIET" -eq 1 ] || printf 'ltop: %s\n' "$*"
}
err() {
    printf 'ltop: error: %s\n' "$*" >&2
}
die() {
    err "$1"
    exit 1
}
usage() {
    cat <<EOF
ltop installer (channel: $INSTALLER_CHANNEL) — macOS arm64/x86_64, Linux x86_64

Usage: sh install.sh [options]

Options:
  --prefix DIR    install directory (default: \$HOME/.local/bin)
  --force         replace a different existing file at the target without
                  prompting (never needed when the expected binary is
                  already installed)
  --uninstall     remove the installed ltop; only files whose SHA-256
                  matches a known ltop binary are removed
  --dry-run       print the plan; download nothing, change nothing
  --quiet         suppress informational output (errors are still printed)
  -h, --help      show this help

Behavior:
  - downloads the pinned release archive over HTTPS only and verifies the
    archive, the release SHA256SUMS file and the extracted binary against
    embedded SHA-256 values before installing
  - installs atomically (temp file + chmod 0755 + mv) to <prefix>/ltop
  - never uses sudo, never modifies shell configuration files, never
    removes the macOS quarantine attribute
  - an existing file at the target that is not the expected binary is
    replaced only with --force or after an interactive yes

Pinned artifacts (tag-pinned, immutable):
  macOS arm64    v0.1.1  ltop-v0.1.1-macos-arm64.zip
  macOS x86_64   v0.1.1  ltop-v0.1.1-macos-x86_64.zip
  Linux x86_64   v0.1.0  ltop-v0.1.0-linux-x86_64.tar.gz

License: proprietary freeware — by installing you accept the license at
$LICENSE_URL
EOF
}
die_usage() {
    err "$1"
    usage >&2
    exit 2
}

# Test-manifest override (explicit, test-only; see header). When set, the
# mapping functions read the synthetic fixture values instead of the
# embedded production values; the hash pipeline itself is unchanged.
MANIFEST_FILE=${LTOP_INSTALL_TEST_MANIFEST:-}
if [ -n "$MANIFEST_FILE" ]; then
    [ -f "$MANIFEST_FILE" ] ||
        die "LTOP_INSTALL_TEST_MANIFEST file not found: $MANIFEST_FILE"
    _mget() {
        # $1 = platform key, $2 = field number (2..7); first line wins
        awk -v p="$1" -v f="$2" '$1 == p {print $f; exit}' "$MANIFEST_FILE"
    }
    platform_version()     { _mget "$1" 2; }
    platform_archive()     { _mget "$1" 3; }
    platform_archive_sha() { _mget "$1" 4; }
    platform_binary_sha()  { _mget "$1" 5; }
    platform_sums_sha()    { _mget "$1" 6; }
    platform_kind()        { _mget "$1" 7; }
fi

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

PREFIX=''
FORCE=0
UNINSTALL=0
DRYRUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || die_usage '--prefix requires a value'
            PREFIX=$2
            shift 2
            ;;
        --prefix=*)
            PREFIX=${1#--prefix=}
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --uninstall)
            UNINSTALL=1
            shift
            ;;
        --dry-run)
            DRYRUN=1
            shift
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die_usage "unknown option: $1 (see --help)"
            ;;
    esac
done

[ "$UNINSTALL" -eq 1 ] && [ "$FORCE" -eq 1 ] &&
    die_usage '--uninstall and --force are mutually exclusive'

# ---------------------------------------------------------------------------
# Base URL (production default; the test-only hook is explicit)
# ---------------------------------------------------------------------------

BASE_URL=${LTOP_RELEASE_BASE_URL:-$DEFAULT_BASE_URL}
case "$BASE_URL" in
    https://*|http://*) : ;;
    *) die "invalid base URL (must start with https:// or http://): $BASE_URL" ;;
esac
BASE_HOST=${BASE_URL#*://}
BASE_HOST=${BASE_HOST%%/*}
BASE_HOST=${BASE_HOST%%:*}
case "$BASE_URL" in
    "$DEFAULT_BASE_URL") ALLOWED_HOSTS=$PROD_ALLOWED_HOSTS ;;
    *)                   ALLOWED_HOSTS=$BASE_HOST ;;
esac

# ---------------------------------------------------------------------------
# Tool checks
# ---------------------------------------------------------------------------

require_tool() {
    # $1 = tool, $2 = hint
    command -v "$1" >/dev/null 2>&1 ||
        die "required tool '$1' not found ($2)"
}

require_tool mktemp 'required to create a safe temporary workspace'
require_tool awk 'required to parse checksum output'

SHA256_TOOL=''
if command -v sha256sum >/dev/null 2>&1; then
    SHA256_TOOL='sha256sum'
elif command -v shasum >/dev/null 2>&1; then
    SHA256_TOOL='shasum -a 256'
else
    die "no SHA-256 tool found (need 'sha256sum' or 'shasum'); hash verification is mandatory"
fi

sha256_of() {
    # $1 = file; prints the lowercase hex SHA-256
    $SHA256_TOOL "$1" | awk '{print $1}'
}

have_curl=0
have_wget=0
command -v curl >/dev/null 2>&1 && have_curl=1
command -v wget >/dev/null 2>&1 && have_wget=1
[ "$have_curl" -eq 1 ] || [ "$have_wget" -eq 1 ] ||
    die "neither curl nor wget is available (one is required to download the release)"

# ---------------------------------------------------------------------------
# Platform detection (Rosetta-aware on macOS)
# ---------------------------------------------------------------------------

detect_platform() {
    os=$(uname -s)
    mach=$(uname -m)
    case "$os" in
        Darwin)
            if [ "$mach" = "arm64" ]; then
                printf 'macos-arm64'
            elif [ "$mach" = "x86_64" ]; then
                # Rosetta: an arm64 Mac running an x86_64 shell reports
                # x86_64. hw.optional.arm64 identifies the real hardware so
                # the arm64 artifact is selected (Rosetta-safe).
                if command -v sysctl >/dev/null 2>&1; then
                    if [ "$(sysctl -in hw.optional.arm64 2>/dev/null)" = "1" ]; then
                        printf 'macos-arm64'
                    else
                        printf 'macos-x86_64'
                    fi
                else
                    printf 'macos-x86_64'
                fi
            else
                return 1
            fi
            ;;
        Linux)
            if [ "$mach" = "x86_64" ]; then
                printf 'linux-x86_64'
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

if [ -n "${LTOP_INSTALL_PLATFORM:-}" ]; then
    PLATFORM=$LTOP_INSTALL_PLATFORM
    case "$PLATFORM" in
        macos-arm64|macos-x86_64|linux-x86_64) : ;;
        *) die "invalid LTOP_INSTALL_PLATFORM: $PLATFORM (expected macos-arm64 | macos-x86_64 | linux-x86_64)" ;;
    esac
    info "platform (test override): $PLATFORM"
else
    PLATFORM=$(detect_platform) ||
        die "unsupported platform: $(uname -s)/$(uname -m). Supported: macOS arm64 (v0.1.1), macOS x86_64 (v0.1.1), Linux x86_64 (v0.1.0). Download manually from $REPO_URL/releases"
fi

VERSION=$(platform_version "$PLATFORM")
ARCHIVE=$(platform_archive "$PLATFORM")
ARCHIVE_SHA=$(platform_archive_sha "$PLATFORM")
BINARY_SHA=$(platform_binary_sha "$PLATFORM")
SUMS_SHA=$(platform_sums_sha "$PLATFORM")
KIND=$(platform_kind "$PLATFORM")

# platform-specific extraction tools
if [ "$KIND" = "zip" ]; then
    require_tool unzip 'required to extract the macOS release archive (zip)'
else
    require_tool tar 'required to extract the Linux release archive (tar.gz)'
fi

# ---------------------------------------------------------------------------
# Prefix validation
# ---------------------------------------------------------------------------

if [ -n "$PREFIX" ]; then
    case "$PREFIX" in
        /*) : ;;
        *) die "--prefix must be an absolute path (got: $PREFIX)" ;;
    esac
    # normalize: strip trailing slashes
    while [ "${PREFIX%/}" != "$PREFIX" ] && [ "$PREFIX" != "/" ]; do
        PREFIX=${PREFIX%/}
    done
else
    PREFIX="${HOME:-}/.local/bin"
    [ -n "${HOME:-}" ] || die 'cannot determine $HOME; pass --prefix explicitly'
fi

# Unsafe prefixes are rejected outright (the installer never escalates, but
# it must not write into core system directories even if run as root).
case "$PREFIX" in
    /|/bin|/sbin|/usr|/usr/bin|/usr/sbin|/usr/lib|/etc|/var|/private|/private/etc|/private/var|/System|/Library)
        die "refusing unsafe install prefix: $PREFIX (use a user-writable directory such as \$HOME/.local/bin)"
        ;;
esac

TARGET="$PREFIX/ltop"

# ---------------------------------------------------------------------------
# Interactive mode
# ---------------------------------------------------------------------------

interactive() {
    if [ -t 0 ]; then
        return 0
    fi
    # Test hook: only honored when the script runs from a file ($0 carries a
    # path), so stdin is free for the piped answer. A piped script
    # (curl ... | sh) has $0 = the shell name and is NEVER interactive —
    # reading from stdin there would consume the script text itself.
    if [ "${LTOP_INSTALL_INTERACTIVE:-}" = "1" ]; then
        case "$0" in
            */*) return 0 ;;
        esac
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Download (HTTPS-only; final-URL host restricted)
# ---------------------------------------------------------------------------

host_of_url() {
    h=${1#*://}
    h=${h%%/*}
    h=${h%%:*}
    printf '%s' "$h"
}

download() {
    # $1 = url, $2 = dest
    dl_url=$1
    dl_dest=$2
    case "$BASE_URL" in
        https://*) dl_proto='=https' ;;
        http://*)  dl_proto='=http' ;;
    esac
    if [ "$have_curl" -eq 1 ]; then
        dl_final=$(curl -fsSL --proto "$dl_proto" --tlsv1.2 \
            --connect-timeout 15 --retry 3 --retry-delay 2 --max-time 600 \
            -o "$dl_dest" -w '%{url_effective}' "$dl_url") ||
            die "download failed: $dl_url"
    else
        # GNU wget (and curl) print the response headers with -S; the last
        # absolute Location: header is the final URL (wget does not expose
        # it any other portable way). A relative Location stays on the
        # original host, so the original URL is the conservative answer.
        dl_hdrs=$(wget -S -q -T 15 -t 3 -O "$dl_dest" "$dl_url" 2>&1) ||
            die "download failed: $dl_url"
        dl_final=$(printf '%s\n' "$dl_hdrs" | awk -v orig="$dl_url" '
            /^[[:space:]]*Location: / { loc = $2 }
            END { if (loc ~ /^https?:\/\//) print loc; else print orig }')
        [ -n "$dl_final" ] || die "download failed: could not determine the final URL of $dl_url"
    fi
    dl_host=$(host_of_url "$dl_final")
    case " $ALLOWED_HOSTS " in
        *" $dl_host "*) : ;;
        *)
            die "download ended at unexpected host '$dl_host' (allowed: $ALLOWED_HOSTS); aborting"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Existing-target handling
# ---------------------------------------------------------------------------

# Decide what to do about an existing file at $TARGET before installing.
# Sets ACTION to 'install' | 'skip' | 'replace' | 'abort'. (A global is used
# instead of command substitution so prompt/info text is not captured.)
check_existing() {
    ABORT_REASON=''
    if [ -L "$TARGET" ]; then
        # symlink: never follow, never overwrite without explicit consent
        link_dest=$(readlink "$TARGET" 2>/dev/null || printf '?')
        info "target is a symlink: $TARGET -> $link_dest"
        if [ "$FORCE" -eq 1 ]; then
            ACTION=replace
        elif interactive; then
            printf 'Replace the symlink %s (currently -> %s)? [y/N] ' "$TARGET" "$link_dest"
            read -r ans || ans=''
            case "$ans" in
                y|Y|yes|YES) ACTION=replace ;;
                *)           ACTION=abort; ABORT_REASON=declined ;;
            esac
        else
            ACTION=abort
            ABORT_REASON=noninteractive
        fi
        return 0
    fi

    if [ ! -e "$TARGET" ]; then
        ACTION=install
        return 0
    fi
    if [ -d "$TARGET" ]; then
        die "$TARGET exists and is a directory; refusing to install"
    fi
    # regular file: hash it (skip hashing fifos/devices — they would block)
    if [ -f "$TARGET" ]; then
        if cur_hash=$(sha256_of "$TARGET" 2>/dev/null); then
            if [ "$cur_hash" = "$BINARY_SHA" ]; then
                ACTION=skip
                return 0
            fi
            if desc=$(describe_known_hash "$cur_hash"); then
                info "existing file looks like $desc (sha256 $cur_hash)"
            else
                info "existing file is not a known ltop binary (sha256 $cur_hash)"
            fi
        else
            info "existing file could not be hashed (unreadable?)"
        fi
    else
        info "existing file is not a regular file (fifo/device?)"
    fi
    if [ "$FORCE" -eq 1 ]; then
        ACTION=replace
    elif interactive; then
        printf 'Replace %s with ltop v%s? [y/N] ' "$TARGET" "$VERSION"
        read -r ans || ans=''
        case "$ans" in
            y|Y|yes|YES) ACTION=replace ;;
            *)           ACTION=abort; ABORT_REASON=declined ;;
        esac
    else
        ACTION=abort
        ABORT_REASON=noninteractive
    fi
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
        info "not installed: $TARGET does not exist (nothing to do)"
        exit 0
    fi
    if [ -L "$TARGET" ]; then
        die "refusing to uninstall: $TARGET is a symlink (remove it manually if you created it)"
    fi
    if ! cur_hash=$(sha256_of "$TARGET" 2>/dev/null); then
        die "refusing to uninstall: cannot hash $TARGET"
    fi
    if ! desc=$(describe_known_hash "$cur_hash"); then
        die "refusing to uninstall: $TARGET does not match any known ltop binary hash (foreign file; remove it manually if you want it gone)"
    fi
    if [ "$DRYRUN" -eq 1 ]; then
        info "dry-run: would remove $TARGET ($desc)"
        exit 0
    fi
    rm -f "$TARGET" || die "could not remove $TARGET"
    info "removed $TARGET ($desc)"
    info "the installer never modified shell configuration files; nothing else to remove"
    exit 0
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

do_install() {
    info "platform: $PLATFORM"
    info "installing ltop v$VERSION from $ARCHIVE"
    info "target: $TARGET"

    if [ "$DRYRUN" -eq 1 ]; then
        info "dry-run: would download $BASE_URL/v$VERSION/$ARCHIVE (sha256 $ARCHIVE_SHA)"
        info "dry-run: would verify the archive, the SHA256SUMS file and the extracted binary"
        if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
            info "dry-run: note — $TARGET already exists; a non-matching file would need --force or an interactive yes"
        fi
        info "dry-run: would install atomically (temp file + chmod 0755 + mv) to $TARGET"
        info "dry-run: no changes made"
        exit 0
    fi

    # --- existing target (before any download: idempotent runs are free) ------
    check_existing
    case "$ACTION" in
        skip)
            info "already installed: $TARGET is ltop v$VERSION (sha256 $BINARY_SHA); nothing to do"
            exit 0
            ;;
        abort)
            if [ "$ABORT_REASON" = "declined" ]; then
                if [ -L "$TARGET" ]; then
                    die "aborted: keeping the symlink $TARGET (answer was not yes)"
                fi
                die "aborted: keeping the existing file $TARGET (answer was not yes)"
            fi
            if [ -L "$TARGET" ]; then
                die "refusing to replace the symlink $TARGET in non-interactive mode (re-run interactively or with --force)"
            fi
            die "refusing to replace the existing file $TARGET in non-interactive mode (re-run interactively or with --force)"
            ;;
        replace)
            [ "$FORCE" -eq 1 ] || info "will replace the existing file at $TARGET (consent given)"
            ;;
    esac

    # --- workspace + cleanup -------------------------------------------------
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/ltop-install.XXXXXX") ||
        die "could not create a temporary workspace (mktemp failed)"
    cleanup() {
        [ -n "${WORK:-}" ] && rm -rf "$WORK"
    }
    trap 'cleanup' EXIT INT TERM

    # --- download + verify the archive --------------------------------------
    info "downloading $ARCHIVE ..."
    download "$BASE_URL/v$VERSION/$ARCHIVE" "$WORK/$ARCHIVE"
    info "verifying archive hash ..."
    got=$(sha256_of "$WORK/$ARCHIVE") || die "could not hash the downloaded archive"
    [ "$got" = "$ARCHIVE_SHA" ] ||
        die "archive hash mismatch (got $got, expected $ARCHIVE_SHA); aborting — nothing was installed"

    # --- download + verify the release SHA256SUMS ----------------------------
    info "downloading SHA256SUMS ..."
    download "$BASE_URL/v$VERSION/SHA256SUMS" "$WORK/SHA256SUMS"
    got_sums=$(sha256_of "$WORK/SHA256SUMS") || die "could not hash the downloaded SHA256SUMS"
    [ "$got_sums" = "$SUMS_SHA" ] ||
        die "SHA256SUMS file hash mismatch (got $got_sums, expected $SUMS_SHA); aborting"
    sums_line=$(awk -v a="$ARCHIVE" '$2 == a {print $1; exit}' "$WORK/SHA256SUMS")
    [ -n "$sums_line" ] || die "SHA256SUMS has no line for $ARCHIVE; aborting"
    [ "$sums_line" = "$ARCHIVE_SHA" ] ||
        die "SHA256SUMS archive hash mismatch (got $sums_line, expected $ARCHIVE_SHA); aborting"

    # --- extract + verify the binary -----------------------------------------
    info "extracting ..."
    mkdir -p "$WORK/extract"
    case "$KIND" in
        zip)
            unzip -q -o "$WORK/$ARCHIVE" -d "$WORK/extract" || die "extraction failed (unzip)"
            ;;
        targz)
            tar -xzf "$WORK/$ARCHIVE" -C "$WORK/extract" || die "extraction failed (tar)"
            ;;
    esac
    case "$KIND" in
        zip)   TOPDIR=${ARCHIVE%.zip} ;;
        targz) TOPDIR=${ARCHIVE%.tar.gz} ;;
    esac
    EXTRACTED="$WORK/extract/$TOPDIR/ltop"
    [ -f "$EXTRACTED" ] || die "extraction did not produce the expected binary ($EXTRACTED)"
    info "verifying binary hash ..."
    got_bin=$(sha256_of "$EXTRACTED") || die "could not hash the extracted binary"
    [ "$got_bin" = "$BINARY_SHA" ] ||
        die "binary hash mismatch (got $got_bin, expected $BINARY_SHA); aborting — nothing was installed"

    # --- atomic install --------------------------------------------------------
    if [ ! -d "$PREFIX" ]; then
        info "creating install directory $PREFIX ..."
        mkdir -p "$PREFIX" || die "could not create $PREFIX"
    fi
    if [ ! -w "$PREFIX" ]; then
        die "$PREFIX is not writable; choose a different --prefix (the installer never uses sudo)"
    fi
    TMPBIN=$(mktemp "$PREFIX/.ltop-install.XXXXXX") ||
        die "could not create the temporary install file in $PREFIX"
    # from here on, a failure must not leave the temp file behind
    tmp_cleanup() {
        [ -n "${TMPBIN:-}" ] && rm -f "$TMPBIN"
        cleanup
    }
    trap 'tmp_cleanup' EXIT INT TERM
    cp -f "$EXTRACTED" "$TMPBIN" || die "could not stage the binary (copy failed)"
    chmod 0755 "$TMPBIN" || die "could not set the executable bit on the staged binary"
    if [ "$ACTION" = "replace" ] && [ -L "$TARGET" ]; then
        # remove the symlink itself; never follow it
        rm "$TARGET" || die "could not remove the symlink $TARGET"
    fi
    mv -f "$TMPBIN" "$TARGET" || die "could not move the staged binary into place (mv failed)"
    TMPBIN=''
    # post-install verification
    got_final=$(sha256_of "$TARGET") || die "could not verify the installed binary"
    [ "$got_final" = "$BINARY_SHA" ] ||
        die "post-install hash mismatch at $TARGET; aborting"
    info "installed ltop v$VERSION to $TARGET (sha256 $BINARY_SHA)"

    # --- macOS quarantine inspection (never auto-removed) ----------------------
    if [ "$(uname -s)" = "Darwin" ] && command -v xattr >/dev/null 2>&1; then
        if xattr -p com.apple.quarantine "$TARGET" >/dev/null 2>&1; then
            info "note: $TARGET carries the macOS quarantine attribute."
            info "the installer never removes it. The SHA-256 checksum matched"
            info "the pinned value above; if Gatekeeper blocks the first run,"
            info "open System Settings -> Privacy & Security and click"
            info "'Open Anyway' next to the ltop entry."
        fi
    fi

    # --- PATH hint ---------------------------------------------------------------
    case ":${PATH:-}:" in
        *":$PREFIX:"*) : ;;
        *)
            info "note: $PREFIX is not in your PATH."
            info "run it as '$TARGET', or add the directory to your PATH in your own shell"
            info "configuration (the installer does not modify shell files)."
            ;;
    esac

    info "license: proprietary freeware — $LICENSE_URL"
    info "done. try: ltop --version"
    exit 0
}

if [ "$UNINSTALL" -eq 1 ]; then
    do_uninstall
else
    do_install
fi
