#!/bin/sh
# ltop installer — macOS (arm64 / x86_64) and Linux (x86_64). POSIX sh.
#
# Tag-pinned one-line install:
#
#   curl --proto '=https' --tlsv1.2 -fsSL \
#     https://raw.githubusercontent.com/pauldckim/ltop-release/install-v2/install.sh | sh
#
# This script is the `install-v2` channel. The previous channel
# `install-v1` remains published and immutable (superseded, never moved);
# both channels pin the same product releases (macOS v0.1.1, Linux
# v0.1.0) — install-v2 hardens the installer itself, not the artifacts.
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
#     rejected. The check runs against the *canonical* prefix: every
#     symlink component of --prefix is resolved (portably, without
#     realpath) and the resolved path is re-checked, so a symlinked prefix
#     cannot alias a write into an unsafe system directory. The installer
#     never escalates privileges.
#   - macOS: the installer never removes the com.apple.quarantine
#     attribute. If the installed binary carries it, it prints
#     checksum-first / System Settings guidance instead.
#   - downloads are HTTPS-only, with no downgrade:
#       * curl runs with --proto '=https' in production, which refuses any
#         redirect hop to a non-HTTPS URL;
#       * the wget fallback enforces TLS >= 1.2 and, on builds that
#         support it, --https-only; it also inspects every redirect hop it
#         prints (Location: headers) and rejects the download when the
#         final URL is not HTTPS in production.
#     Documented limitation: a downloader that exposes neither its
#     redirect hops nor a no-downgrade flag cannot be fully chain-audited;
#     the four-hash pipeline remains the binding guarantee (substituted
#     content fails verification before install).
#   - interrupts (Ctrl-C / SIGINT, SIGTERM): the traps clean up the
#     temporary workspace and the staged file, print a clear "interrupted"
#     message, and exit with the conventional code (130 for SIGINT, 143
#     for SIGTERM); nothing is ever left half-installed.
#
# Test-only environment hooks (documented so production defaults cannot be
# weakened inadvertently; the hash pipeline is enforced in all modes, so a
# base-URL override alone cannot substitute different artifacts):
#   LTOP_RELEASE_BASE_URL   alternate download base, default:
#                           https://github.com/pauldckim/ltop-release/releases/download
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
#   LTOP_INSTALL_TEST_PLATFORM
#                           bypass detection: macos-arm64 | macos-x86_64 |
#                           linux-x86_64. TEST-ONLY: honored only when
#                           LTOP_INSTALL_TEST_MANIFEST is set and valid, so
#                           a leaked platform variable alone can never
#                           select a different architecture in production.
#   LTOP_INSTALL_INTERACTIVE=1
#                           force the interactive prompt path (default:
#                           prompt only when stdin is a terminal)
#
# Exit codes: 0 = installed / already installed / uninstalled / dry-run ok
#             1 = runtime failure (hash mismatch, download failure,
#                 refused replacement, unsupported platform, ...)
#             2 = usage error
#             130 = interrupted by SIGINT (Ctrl-C); cleaned up
#             143 = interrupted by SIGTERM; cleaned up
#
# License: ltop is proprietary freeware. By installing you accept the
# license at https://github.com/pauldckim/ltop-release/blob/main/LICENSE.md
# (the full text ships inside every release archive as LICENSE.md).

set -u

INSTALLER_CHANNEL='install-v2'
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
  - downloads the pinned release archive over HTTPS only (no downgrade;
    redirect hops are host-restricted) and verifies the archive, the
    release SHA256SUMS file and the extracted binary against embedded
    SHA-256 values before installing
  - installs atomically (temp file + chmod 0755 + mv) to <prefix>/ltop
  - resolves symlink components of --prefix and re-checks the resolved
    path against the unsafe-prefix list (no alias bypass)
  - never uses sudo, never modifies shell configuration files, never
    removes the macOS quarantine attribute
  - an existing file at the target that is not the expected binary is
    replaced only with --force or after an interactive yes
  - on Ctrl-C / SIGTERM: cleans up and exits 130 / 143

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

# ---------------------------------------------------------------------------
# Cleanup and signal handling.
#
# The traps are installed before any workspace exists, so an interrupt at
# any later point cleans up and exits with a clear message and the
# conventional code (128 + signal number). The EXIT trap does the actual
# cleanup; the INT/TERM traps only announce and exit, which runs the EXIT
# trap exactly once. WORK/TMPBIN are empty until created, so cleanup is a
# no-op early on.
# ---------------------------------------------------------------------------

cleanup() {
    [ -n "${TMPBIN:-}" ] && rm -f -- "$TMPBIN" 2>/dev/null
    [ -n "${WORK:-}" ] && rm -rf -- "$WORK" 2>/dev/null
}
trap 'cleanup' EXIT
trap 'printf "ltop: interrupted (Ctrl-C); cleaning up — nothing was installed\n" >&2; exit 130' INT
trap 'printf "ltop: interrupted (terminated); cleaning up — nothing was installed\n" >&2; exit 143' TERM

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
    # $1 = file; prints the lowercase hex SHA-256; returns non-zero on any
    # read or hashing failure.
    # The file is copied to a private temp file and hashed via stdin, so the
    # hash tool never sees the original file name: no GNU coreutils
    # backslash-escaping of file names in the output line (a name containing
    # a backslash prefixes the digest line with '\'), no path-dependent tool
    # quirks, and an unreadable file fails the copy step here instead of
    # producing an empty "hash" that downstream checks would misread. The
    # tool's own exit status is preserved (checked before the awk field
    # split), and the digest is validated as exactly 64 lowercase hex chars.
    tf=$(mktemp "${TMPDIR:-/tmp}/ltop-sha256.XXXXXX") || return 1
    if ! cat -- "$1" > "$tf" 2>/dev/null; then
        rm -f -- "$tf"
        return 1
    fi
    raw=$($SHA256_TOOL < "$tf" 2>/dev/null)
    rc=$?
    rm -f -- "$tf"
    [ "$rc" -eq 0 ] || return 1
    h=$(printf '%s\n' "$raw" | awk 'NR==1 {print $1}')
    case "$h" in
        *[!0-9a-f]*) return 1 ;;
    esac
    [ "${#h}" -eq 64 ] || return 1
    printf '%s\n' "$h"
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

# The platform override is TEST-ONLY and requires the test manifest: a
# leaked platform variable alone must never be able to select a different
# architecture in production (it would download and install the wrong
# artifact for the detected machine). The removed v1 name fails loudly
# rather than being silently ignored.
if [ -n "${LTOP_INSTALL_PLATFORM:-}" ]; then
    die "LTOP_INSTALL_PLATFORM is a removed v1 test hook: production runs must not set it; tests must set LTOP_INSTALL_TEST_PLATFORM together with LTOP_INSTALL_TEST_MANIFEST"
fi
if [ -n "${LTOP_INSTALL_TEST_PLATFORM:-}" ]; then
    [ -n "$MANIFEST_FILE" ] ||
        die "LTOP_INSTALL_TEST_PLATFORM is test-only and requires LTOP_INSTALL_TEST_MANIFEST (a leaked platform variable must not select the architecture in production)"
    PLATFORM=$LTOP_INSTALL_TEST_PLATFORM
    case "$PLATFORM" in
        macos-arm64|macos-x86_64|linux-x86_64) : ;;
        *) die "invalid LTOP_INSTALL_TEST_PLATFORM: $PLATFORM (expected macos-arm64 | macos-x86_64 | linux-x86_64)" ;;
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
# Path canonicalization (portable; no realpath / readlink -f dependency)
# ---------------------------------------------------------------------------

# Resolve the symlinks of an absolute path, component by component. The
# path need not exist yet (the installer creates its final component).
# Prints the canonical path; returns 1 if a symlink target cannot be read
# or the result would escape above the filesystem root.
canonicalize_path() {
    _cp=$1
    case "$_cp" in
        /*) : ;;
        *) return 1 ;;
    esac
    while [ "${_cp%/}" != "$_cp" ] && [ "$_cp" != "/" ]; do
        _cp=${_cp%/}
    done
    # split into a component stack (leading-slash separated)
    _rest=$_cp
    _stack=''
    while [ -n "$_rest" ]; do
        case "$_rest" in
            */*) _comp=${_rest%%/*}; _rest=${_rest#*/} ;;
            *)   _comp=$_rest; _rest='' ;;
        esac
        case "$_comp" in
            ''|.) ;;
            *)   _stack="$_stack/$_comp" ;;
        esac
    done
    _out=''
    _nlinks=0
    while [ -n "$_stack" ]; do
        _comp=${_stack%%/*}
        case "$_stack" in
            */*) _stack=${_stack#*/} ;;
            *)   _stack='' ;;
        esac
        [ -n "$_comp" ] || continue   # leading separator artifact
        if [ "$_comp" = ".." ]; then
            [ -n "$_out" ] || return 1   # would escape above the root
            _out=${_out%/*}
            [ -n "$_out" ] || _out='/'
            continue
        fi
        case "$_out" in
            ''|/) _cand="/$_comp" ;;
            *)    _cand="$_out/$_comp" ;;
        esac
        if [ -L "$_cand" ]; then
            # bound the resolution like the kernel does (ELOOP after 40
            # symlinks) so a self-referential chain cannot loop forever
            _nlinks=$((_nlinks + 1))
            [ "$_nlinks" -le 40 ] || return 1
            _tgt=$(readlink -- "$_cand" 2>/dev/null) || return 1
            # splice the target's components in front of the remaining
            # stack; a relative target stays in the link's own directory
            # (_out), an absolute target restarts from the root
            _tx=$_tgt
            _pre=''
            while [ -n "$_tx" ]; do
                case "$_tx" in
                    */*) _tc=${_tx%%/*}; _tx=${_tx#*/} ;;
                    *)   _tc=$_tx; _tx='' ;;
                esac
                case "$_tc" in
                    ''|.) ;;
                    *)   _pre="$_pre/$_tc" ;;
                esac
            done
            # the remaining stack may have lost its leading separator when
            # the symlink component was popped; restore it before splicing
            case "$_stack" in
                ''|/*) : ;;
                *)     _stack="/$_stack" ;;
            esac
            _stack="$_pre$_stack"
            case "$_tgt" in
                /*) _out='' ;;
            esac
            continue
        fi
        case "$_out" in
            ''|/) _out="/$_comp" ;;
            *)    _out="$_out/$_comp" ;;
        esac
    done
    [ -n "$_out" ] || _out='/'
    printf '%s\n' "$_out"
}

# ---------------------------------------------------------------------------
# Prefix validation (literal + canonical, so symlinks cannot alias
# writes into unsafe system directories)
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

unsafe_prefix() {
    case "$1" in
        /|/bin|/sbin|/usr|/usr/bin|/usr/sbin|/usr/lib|/etc|/var|/private|/private/etc|/private/var|/System|/Library)
            return 0 ;;
    esac
    return 1
}

# Unsafe prefixes are rejected outright (the installer never escalates, but
# it must not write into core system directories even if run as root).
if unsafe_prefix "$PREFIX"; then
    die "refusing unsafe install prefix: $PREFIX (use a user-writable directory such as \$HOME/.local/bin)"
fi

# Canonicalize and re-check: a symlinked prefix component that points into
# an unsafe system directory is an alias attack and is refused; a benign
# alias (e.g. /tmp -> /private/tmp on macOS) is resolved and used.
PREFIX_REAL=$(canonicalize_path "$PREFIX") ||
    die "cannot resolve the install prefix $PREFIX (unreadable symlink component?); refusing to install"
if unsafe_prefix "$PREFIX_REAL"; then
    die "refusing unsafe install prefix: $PREFIX resolves to $PREFIX_REAL (use a user-writable directory such as \$HOME/.local/bin)"
fi
if [ "$PREFIX_REAL" != "$PREFIX" ]; then
    info "prefix $PREFIX resolves to $PREFIX_REAL (symlink); installing there"
    PREFIX=$PREFIX_REAL
fi

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
# Download (HTTPS-only, no downgrade; every redirect hop's host restricted)
# ---------------------------------------------------------------------------

host_of_url() {
    h=${1#*://}
    h=${h%%/*}
    h=${h%%:*}
    printf '%s' "$h"
}

scheme_of_url() {
    s=${1%%:*}
    printf '%s' "$s"
}

# Join a possibly-relative redirect target against the URL it came from.
url_join() {
    # $1 = base url, $2 = target
    case "$2" in
        http://*|https://*) printf '%s' "$2" ;;
        //*)                printf '%s://%s' "$(scheme_of_url "$1")" "${2#//}" ;;
        /*)                 printf '%s://%s' "$(scheme_of_url "$1")" "$(host_of_url "$1")$2" ;;
        *)                  printf '%s' "$1$2" ;;
    esac
}

# Check one redirect hop (or the final URL) of a download.
check_hop() {
    # $1 = hop url, $2 = hop kind ("redirect hop" | "final URL")
    case " $ALLOWED_HOSTS " in
        *" $(host_of_url "$1") "*) : ;;
        *)
            die "download $2 ended at unexpected host '$(host_of_url "$1")' (allowed: $ALLOWED_HOSTS); aborting"
            ;;
    esac
    case "$BASE_URL" in
        https://*)
            case "$1" in
                https://*) : ;;
                *) die "download $2 downgraded to non-HTTPS ($1); refusing" ;;
            esac
            ;;
    esac
}

# wget flag support is detected once (portable across GNU wget versions and
# busybox builds): --https-only (no http downgrade, GNU >= 1.21) and
# --secure-protocol (minimum TLS version, GNU >= 1.15).
WGET_HTTPS_ONLY=''
WGET_TLS_MIN=''
if [ "$have_wget" -eq 1 ]; then
    _wget_help=$(wget --help 2>&1 || true)
    case "$_wget_help" in
        *'--https-only'*) WGET_HTTPS_ONLY='--https-only' ;;
    esac
    case "$_wget_help" in
        *'--secure-protocol'*) WGET_TLS_MIN='--secure-protocol=TLSv1_2' ;;
    esac
fi

download() {
    # $1 = url, $2 = dest
    dl_url=$1
    dl_dest=$2
    case "$BASE_URL" in
        https://*) dl_proto='=https' ;;
        http://*)  dl_proto='=http' ;;
    esac
    if [ "$have_curl" -eq 1 ]; then
        # --proto '=https' (production) applies to every redirect hop as
        # well: curl refuses to follow a hop to a non-allowed protocol, so
        # an HTTPS -> HTTP downgrade fails the download instead of
        # succeeding at a weaker URL.
        dl_final=$(curl -fsSL --proto "$dl_proto" --tlsv1.2 \
            --connect-timeout 15 --retry 3 --retry-delay 2 --max-time 600 \
            -o "$dl_dest" -w '%{url_effective}' "$dl_url") ||
            die "download failed: $dl_url"
    else
        # wget: HTTPS-only as far as the build allows. --https-only (GNU
        # >= 1.21) refuses http URLs and downgrades outright;
        # --secure-protocol pins the minimum TLS version. Both apply only
        # to HTTPS bases: with an http:// test base, --https-only would
        # refuse the base URL itself. With -S wget prints the response
        # headers of every hop to stderr; the Location: headers are the
        # redirect chain.
        case "$BASE_URL" in
            https://*) dl_wget_flags="$WGET_HTTPS_ONLY $WGET_TLS_MIN" ;;
            *)         dl_wget_flags='' ;;
        esac
        dl_hdrs=$(wget -S -q -T 15 -t 3 -O "$dl_dest" \
            $dl_wget_flags "$dl_url" 2>&1) ||
            die "download failed: $dl_url"
        # Inspect the chain: every hop's host must be allowed, and (in
        # production) no hop may downgrade to HTTP. The walk runs in the
        # main shell (not a command substitution) so a refused hop aborts
        # the installer. A redirect chain that wget did not print
        # (non-standard build) falls back to checking the original URL,
        # which is the conservative answer.
        dl_final=$dl_url
        dl_locs=$(printf '%s\n' "$dl_hdrs" | awk '
            /^[[:space:]]*Location: / { loc = $2; sub(/\r$/, "", loc); print loc }')
        if [ -n "$dl_locs" ]; then
            # IFS=newline word splitting (a URL carries no newline) with
            # globbing disabled; the loop runs in the main shell so a
            # refused hop aborts the installer. (A heredoc would expand
            # the hop text — never do that with server-controlled input.)
            set -f
            _old_ifs=$IFS
            IFS='
'
            for loc in $dl_locs; do
                [ -n "$loc" ] || continue
                dl_final=$(url_join "$dl_final" "$loc")
                check_hop "$dl_final" "redirect hop"
            done
            IFS=$_old_ifs
            set +f
        fi
        [ -n "$dl_final" ] || die "download failed: could not determine the final URL of $dl_url"
    fi
    check_hop "$dl_final" "final URL"
}

# ---------------------------------------------------------------------------
# Existing-target handling
# ---------------------------------------------------------------------------

# Decide what to do about an existing file at $TARGET before installing.
# Sets ACTION to 'install' | 'skip' | 'replace' | 'abort'. (A global is used
# instead of command substitution so prompt/info text is not captured.)
#
# resolve_existing is the pure state resolution (no prompts, no consent):
# 'skip' when the expected binary is already in place, 'install' when the
# target is absent, 'replace' when --force consents, 'abort' otherwise.
# check_existing wraps it with the interactive consent prompt for real
# runs; --dry-run uses resolve_existing directly so it never prompts.
resolve_existing() {
    ABORT_REASON=''
    if [ -L "$TARGET" ]; then
        # symlink: never follow, never overwrite without explicit consent
        link_dest=$(readlink "$TARGET" 2>/dev/null || printf '?')
        info "target is a symlink: $TARGET -> $link_dest"
        if [ "$FORCE" -eq 1 ]; then
            ACTION=replace
        else
            ACTION=abort
            ABORT_REASON=consent
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
    else
        ACTION=abort
        ABORT_REASON=consent
    fi
}

check_existing() {
    resolve_existing
    if [ "$ACTION" = "abort" ] && [ "$ABORT_REASON" = "consent" ]; then
        if interactive; then
            if [ -L "$TARGET" ]; then
                link_dest=$(readlink "$TARGET" 2>/dev/null || printf '?')
                printf 'Replace the symlink %s (currently -> %s)? [y/N] ' "$TARGET" "$link_dest"
            else
                printf 'Replace %s with ltop v%s? [y/N] ' "$TARGET" "$VERSION"
            fi
            read -r ans || ans=''
            case "$ans" in
                y|Y|yes|YES) ACTION=replace ;;
                *)           ABORT_REASON=declined ;;
            esac
        else
            ABORT_REASON=noninteractive
        fi
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
        # Resolve the existing-target state (no download, no prompt, no
        # changes) so the plan says what a real run would do.
        resolve_existing
        case "$ACTION" in
            skip)
                info "dry-run: $TARGET already holds the expected ltop v$VERSION binary; a real run would be a no-op"
                ;;
            abort)
                if [ -L "$TARGET" ]; then
                    info "dry-run: a real run would stop here: $TARGET is a symlink (never followed) and would need --force or an interactive yes"
                else
                    info "dry-run: a real run would stop here: $TARGET exists and would need --force or an interactive yes"
                fi
                ;;
            replace)
                info "dry-run: a real run would replace the existing file at $TARGET (consent: --force)"
                ;;
            install)
                info "dry-run: $TARGET does not exist yet; a real run would create it"
                ;;
        esac
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
    # cleanup + the INT/TERM traps were installed up front (see above)

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
    # from here on, a failure (or interrupt) must not leave the temp file
    # behind: the up-front cleanup/INT/TERM traps handle it
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
