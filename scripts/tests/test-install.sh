#!/bin/sh
# test-install.sh — deterministic tests for the root install.sh.
#
# Public-safe: builds a synthetic fixture release (version 9.9.9, fake
# binaries, real hashes of the fixtures only) under a mktemp directory,
# serves it from a loopback HTTP server, and drives install.sh through the
# documented test-only environment hooks:
#
#   LTOP_RELEASE_BASE_URL      -> the loopback fixture server
#   LTOP_INSTALL_TEST_MANIFEST -> the fixture mapping (hashes of the fixtures)
#   LTOP_INSTALL_TEST_PLATFORM -> each of the three platform keys
#                                 (test-only: requires the manifest)
#   LTOP_INSTALL_INTERACTIVE=1 -> the interactive prompt path
#
# The production defaults (embedded mapping, the GitHub base URL, the
# HTTPS-only download policy) are asserted separately and are never
# weakened by the hooks: the hash pipeline runs identically in both modes.
#
# Adversarial regression tests (install-v2 hardening):
#   T30  signals: SIGINT/SIGTERM mid-download -> interrupted message,
#        exit 130/143, workspace and staged file cleaned up
#   T31  sha256: target path containing a backslash (GNU coreutils
#        backslash-escaping of file names) and an unreadable existing file
#   T32  symlinked prefix: alias into an unsafe system directory is
#        refused; benign aliases are resolved; symlink loops are refused
#   T33  downloads: redirect-chain inspection (a foreign intermediate hop
#        is refused), HTTPS downgrade rejection (unit), no-downgrade flags
#
# No network access beyond 127.0.0.0/8, no real release data, no system
# PATH changes, no shell rc changes (asserted).
#
# POSIX sh. Requires: python3 (fixture server + zip building), tar,
# sha256sum or shasum, awk. curl or wget (the wget-fallback test is
# skipped with reason when wget is absent).
#
# Usage: sh scripts/tests/test-install.sh
# Exit codes: 0 = all tests pass, 1 = at least one test failed.

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$(dirname -- "$here")")
INSTALL="$repo_root/install.sh"

[ -f "$INSTALL" ] || { echo "error: $INSTALL not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ltop-test-install.XXXXXX") || exit 1
SRV_PIDS=''
cleanup() {
    [ -n "$SRV_PIDS" ] && kill $SRV_PIDS 2>/dev/null
    rm -rf "$tmp"
}
trap 'cleanup' EXIT INT TERM

# --- sha256 helper -----------------------------------------------------------
# Hash via stdin so the tool never sees the file name: GNU coreutils
# backslash-escapes file names in its output (a '\'-prefixed digest line),
# which would corrupt the digest for paths containing a backslash.

if command -v sha256sum >/dev/null 2>&1; then
    sha256_of() { sha256sum < "$1" | awk '{print $1}'; }
else
    sha256_of() { shasum -a 256 < "$1" | awk '{print $1}'; }
fi

# --- test harness ------------------------------------------------------------

tests=0
failed=0
skipped=0

pass() {
    tests=$((tests + 1))
    echo "PASS $1"
}
fail() {
    tests=$((tests + 1))
    echo "FAIL $1${2:+ ($2)}"
    [ -n "${3:-}" ] && sed 's/^/    /' "$3" | tail -10
    failed=$((failed + 1))
}
skip() {
    skipped=$((skipped + 1))
    echo "SKIP $1 ($2)"
}

# expect_rc <name> <wanted_rc> <output_file> <actual_rc>
expect_rc() {
    if [ "$4" -eq "$2" ]; then
        pass "$1"
    else
        fail "$1" "exit $4, wanted $2" "$3"
    fi
}

# expect_grep <name> <file> <pattern>
expect_grep() {
    if grep -q "$3" "$2"; then
        pass "$1"
    else
        fail "$1" "pattern not found: $3" "$2"
    fi
}

# expect_file_grep <name> <file> <pattern>  (same as expect_grep, clearer name)
expect_file_grep() {
    expect_grep "$1" "$2" "$3"
}

# --- fixture build -----------------------------------------------------------

# Fixture "binaries": tiny POSIX sh scripts that print a version line.
# Distinct content per platform so the hashes differ.
make_fixture_bin() {
    # $1 = path, $2 = label
    printf '#!/bin/sh\n# ltop fixture binary (%s)\necho "ltop 9.9.9 %s"\n' "$2" "$2" > "$1"
    chmod 755 "$1"
}

# (Re)build the fixture archives in $tmp/docroot/v9.9.9 from the pristine
# fixture binaries in $tmp/binfix, then re-record SHA256SUMS + manifest.
make_archives() {
    for plat in macos-arm64 macos-x86_64 linux-x86_64; do
        case $plat in
            macos-arm64)   top=ltop-v9.9.9-macos-arm64;   arch=ltop-v9.9.9-macos-arm64.zip; kind=zip ;;
            macos-x86_64)  top=ltop-v9.9.9-macos-x86_64;  arch=ltop-v9.9.9-macos-x86_64.zip; kind=zip ;;
            linux-x86_64)  top=ltop-v9.9.9-linux-x86_64;  arch=ltop-v9.9.9-linux-x86_64.tar.gz; kind=targz ;;
        esac
        stage="$tmp/stage-$plat"
        rm -rf "$stage"
        mkdir -p "$stage/$top"
        printf 'fixture license\n' > "$stage/$top/LICENSE.md"
        printf 'fixture readme\n' > "$stage/$top/README.txt"
        printf 'fixture notices\n' > "$stage/$top/THIRD_PARTY_NOTICES.md"
        cp "$tmp/binfix/$top/ltop" "$stage/$top/ltop"
        chmod 755 "$stage/$top/ltop"
        case $kind in
            zip)
                python3 - "$stage" "$tmp/docroot/v9.9.9/$arch" "$top" <<'PY'
import os, sys, zipfile
stage, out, top = sys.argv[1], sys.argv[2], sys.argv[3]
files = ["LICENSE.md", "README.txt", "THIRD_PARTY_NOTICES.md", "ltop"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        p = os.path.join(stage, top, f)
        mode = 0o755 if f == "ltop" else 0o644
        zi = zipfile.ZipInfo("%s/%s" % (top, f), date_time=(2026, 9, 7, 0, 0, 0))
        zi.external_attr = mode << 16
        with open(p, "rb") as fh:
            z.writestr(zi, fh.read())
PY
                ;;
            targz)
                (cd "$stage" && tar -czf "$tmp/docroot/v9.9.9/$arch" "$top")
                ;;
        esac
        rm -rf "$stage"
    done
    record_sums_manifest
}

record_sums_manifest() {
    # SHA256SUMS over the fixture archives
    (cd "$tmp/docroot/v9.9.9" &&
        {
            for f in ltop-v9.9.9-linux-x86_64.tar.gz ltop-v9.9.9-macos-arm64.zip ltop-v9.9.9-macos-x86_64.zip; do
                printf '%s  %s\n' "$(sha256_of "$f")" "$f"
            done
        } > SHA256SUMS)
    # Manifest for LTOP_INSTALL_TEST_MANIFEST
    {
        for plat in macos-arm64 macos-x86_64 linux-x86_64; do
            case $plat in
                macos-arm64)   arch=ltop-v9.9.9-macos-arm64.zip; kind=zip ;;
                macos-x86_64)  arch=ltop-v9.9.9-macos-x86_64.zip; kind=zip ;;
                linux-x86_64)  arch=ltop-v9.9.9-linux-x86_64.tar.gz; kind=targz ;;
            esac
            printf '%s 9.9.9 %s %s %s %s %s\n' \
                "$plat" "$arch" \
                "$(sha256_of "$tmp/docroot/v9.9.9/$arch")" \
                "$(sha256_of "$tmp/binfix/ltop-v9.9.9-$plat/ltop")" \
                "$(sha256_of "$tmp/docroot/v9.9.9/SHA256SUMS")" \
                "$kind"
        done
    } > "$tmp/manifest"
}

build_fixtures() {
    # pristine fixture binaries first
    for plat in macos-arm64 macos-x86_64 linux-x86_64; do
        case $plat in
            macos-arm64)  top=ltop-v9.9.9-macos-arm64 ;;
            macos-x86_64) top=ltop-v9.9.9-macos-x86_64 ;;
            linux-x86_64) top=ltop-v9.9.9-linux-x86_64 ;;
        esac
        mkdir -p "$tmp/binfix/$top"
        make_fixture_bin "$tmp/binfix/$top/ltop" "$plat"
    done
    make_archives
}

# --- loopback servers ---------------------------------------------------------

pick_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

wait_port() {
    # $1 = port
    i=0
    while [ "$i" -lt 50 ]; do
        if python3 -c "import socket; socket.create_connection(('127.0.0.1', $1), 0.2).close()" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    return 1
}

# --- fixture env --------------------------------------------------------------

BASE=''
MANIFEST=''
run_inst() {
    # run_inst <name> <platform> <prefix> [extra args...]
    # Runs install.sh with the fixture env; output -> $tmp/out-<name>.
    # Sets RC.
    name=$1
    plat=$2
    pref=$3
    shift 3
    env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
        LTOP_INSTALL_TEST_PLATFORM="$plat" sh "$INSTALL" --prefix "$pref" "$@" \
        > "$tmp/out-$name" 2>&1
    RC=$?
}

run_inst_interactive() {
    # run_inst_interactive <name> <answer> <platform> <prefix> [extra args...]
    name=$1
    answer=$2
    plat=$3
    pref=$4
    shift 4
    printf '%s\n' "$answer" |
        env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
            LTOP_INSTALL_TEST_PLATFORM="$plat" LTOP_INSTALL_INTERACTIVE=1 \
            sh "$INSTALL" --prefix "$pref" "$@" > "$tmp/out-$name" 2>&1
    RC=$?
}

# =============================================================================
# Build fixtures + start servers
# =============================================================================

mkdir -p "$tmp/docroot/v9.9.9" "$tmp/evil"
build_fixtures

PORT=$(pick_port)
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$tmp/docroot" >/dev/null 2>&1 &
SRV_PIDS="$SRV_PIDS $!"
wait_port "$PORT" || { echo "error: fixture server did not start" >&2; exit 1; }
BASE="http://127.0.0.1:$PORT"
MANIFEST="$tmp/manifest"

# redirect server: 302 everything to a *different host string* on loopback
# (localhost resolves to 127.0.0.1, but the installer's final-URL host check
# is host-based, so the redirect must be rejected)
PORT_R=$(pick_port)
PORT_E=$(pick_port)
cat > "$tmp/redirect_server.py" <<'PY'
import http.server, sys
port = int(sys.argv[1])
target = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(302)
        self.send_header("Location", target)
        self.end_headers()
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
python3 -m http.server "$PORT_E" --bind 127.0.0.1 --directory "$tmp/evil" >/dev/null 2>&1 &
SRV_PIDS="$SRV_PIDS $!"
python3 "$tmp/redirect_server.py" "$PORT_R" "http://localhost:$PORT_E/evil" >/dev/null 2>&1 &
SRV_PIDS="$SRV_PIDS $!"
wait_port "$PORT_R" || { echo "error: redirect server did not start" >&2; exit 1; }
wait_port "$PORT_E" || { echo "error: evil server did not start" >&2; exit 1; }
printf 'evil payload\n' > "$tmp/evil/evil"

# fresh prefix dirs
mkdir -p "$tmp/pfx"

# =============================================================================
# T1: syntax
# =============================================================================

sh -n "$INSTALL" > "$tmp/out-t1" 2>&1
expect_rc "T1 install.sh passes sh -n" 0 "$tmp/out-t1" $?

# =============================================================================
# T2: --help
# =============================================================================

env sh "$INSTALL" --help > "$tmp/out-t2" 2>&1
expect_rc "T2 --help exits 0" 0 "$tmp/out-t2" $?
expect_grep "T2 help shows usage" "$tmp/out-t2" 'Usage: sh install.sh'
expect_grep "T2 help names the channel" "$tmp/out-t2" 'channel: install-v3'
expect_grep "T2 help shows the license link" "$tmp/out-t2" 'github.com/pauldckim/ltop-release/blob/main/LICENSE.md'

# =============================================================================
# T3: usage errors
# =============================================================================

env sh "$INSTALL" --bogus > "$tmp/out-t3a" 2>&1
expect_rc "T3 unknown option exits 2" 2 "$tmp/out-t3a" $?
expect_grep "T3 names the bad option" "$tmp/out-t3a" 'unknown option: --bogus'

env sh "$INSTALL" --uninstall --force > "$tmp/out-t3b" 2>&1
expect_rc "T3 --uninstall --force exits 2" 2 "$tmp/out-t3b" $?

env sh "$INSTALL" --prefix > "$tmp/out-t3c" 2>&1
expect_rc "T3 --prefix without value exits 2" 2 "$tmp/out-t3c" $?

# =============================================================================
# T4: production mapping is embedded and tag-pinned (no fixture env)
# =============================================================================

# T4a: no env at all — the *detected* platform's pinned mapping is used and
# the production GitHub base URL is in effect (the platform override is
# test-only since install-v2, so a production run cannot be steered).
env sh "$INSTALL" --prefix "$tmp/pfx/prod1" --dry-run > "$tmp/out-t4a" 2>&1
expect_rc "T4 detected-platform dry-run exits 0" 0 "$tmp/out-t4a" $?
expect_grep "T4 uses the GitHub base URL" "$tmp/out-t4a" 'https://github.com/pauldckim/ltop-release/releases/download'
t4plat=$(sed -n 's/^ltop: platform: //p' "$tmp/out-t4a" | head -1)
case "$t4plat" in
    macos-arm64)
        t4arch='ltop-v0.1.2-macos-arm64.zip'
        t4sha='d349b64375fb8263011a625c5f585db0930affdf2c0d0c3e2deb268d84780b47' ;;
    macos-x86_64)
        t4arch='ltop-v0.1.2-macos-x86_64.zip'
        t4sha='0fe80dfdb36616059a56a645c3d3eeddf1bd5257150e48141fb063b0b77f2c7c' ;;
    linux-x86_64)
        t4arch='ltop-v0.1.2-linux-x86_64.tar.gz'
        t4sha='f11144035a054c0c944f648045a25d5bc68e1def2236b7ed60cc6179bcb56bba' ;;
    *)
        t4arch='' ;;
esac
if [ -n "$t4arch" ]; then
    expect_grep "T4 detected platform ($t4plat) pins its archive" "$tmp/out-t4a" "$t4arch"
    expect_grep "T4 detected platform archive sha embedded" "$tmp/out-t4a" "$t4sha"
else
    fail "T4 detected platform recognized" "unknown platform: $t4plat" "$tmp/out-t4a"
fi

# T4b: unit-test the embedded mapping functions for ALL three platforms
# (extracted from install.sh, so any host covers the full pinned record).
t4b_fns="$tmp/t4b-fns.sh"
: > "$t4b_fns"
for fn in platform_version platform_archive platform_archive_sha \
          platform_binary_sha platform_sums_sha platform_kind; do
    awk -v f="$fn" '
        $0 ~ "^" f "\\(\\) \\{" { fnd = 1 }
        fnd { print }
        fnd && $0 == "}" { exit }' "$INSTALL" >> "$t4b_fns"
done
t4b_out=$(sh -c '
    . "$1"
    for p in macos-arm64 macos-x86_64 linux-x86_64; do
        printf "%s|%s|%s|%s|%s|%s|%s\n" "$p" \
            "$(platform_version "$p")" "$(platform_archive "$p")" \
            "$(platform_archive_sha "$p")" "$(platform_binary_sha "$p")" \
            "$(platform_sums_sha "$p")" "$(platform_kind "$p")"
    done' _ "$t4b_fns")
t4b_want_macos_arm64='macos-arm64|0.1.2|ltop-v0.1.2-macos-arm64.zip|d349b64375fb8263011a625c5f585db0930affdf2c0d0c3e2deb268d84780b47|a8f8ab16ec7e37c8121b86d7966c47fa1ba4292933696f068d11a33b6b1a9a0c|3a76bbfcc4df41f617fb7149ee74927c5897fae6a67cad40103dfb779ee22850|zip'
t4b_want_macos_x86_64='macos-x86_64|0.1.2|ltop-v0.1.2-macos-x86_64.zip|0fe80dfdb36616059a56a645c3d3eeddf1bd5257150e48141fb063b0b77f2c7c|24362c464980074810762ec626b80e33aa98bac6743179462bbe5452dce69546|3a76bbfcc4df41f617fb7149ee74927c5897fae6a67cad40103dfb779ee22850|zip'
t4b_want_linux_x86_64='linux-x86_64|0.1.2|ltop-v0.1.2-linux-x86_64.tar.gz|f11144035a054c0c944f648045a25d5bc68e1def2236b7ed60cc6179bcb56bba|84a84b7c56e399f9178703da71be8894f02a394fef2ce36d1e01f5d3e41414c4|3a76bbfcc4df41f617fb7149ee74927c5897fae6a67cad40103dfb779ee22850|targz'
t4b_got_arm64=$(printf '%s\n' "$t4b_out" | sed -n '1p')
t4b_got_x86_64=$(printf '%s\n' "$t4b_out" | sed -n '2p')
t4b_got_linux=$(printf '%s\n' "$t4b_out" | sed -n '3p')
if [ "$t4b_got_arm64" = "$t4b_want_macos_arm64" ]; then
    pass "T4 embedded mapping: macos-arm64"
else
    fail "T4 embedded mapping: macos-arm64" "got: $t4b_got_arm64"
fi
if [ "$t4b_got_x86_64" = "$t4b_want_macos_x86_64" ]; then
    pass "T4 embedded mapping: macos-x86_64"
else
    fail "T4 embedded mapping: macos-x86_64" "got: $t4b_got_x86_64"
fi
if [ "$t4b_got_linux" = "$t4b_want_linux_x86_64" ]; then
    pass "T4 embedded mapping: linux-x86_64"
else
    fail "T4 embedded mapping: linux-x86_64" "got: $t4b_got_linux"
fi

# =============================================================================
# T5: platform override is test-only (F5) + invalid base URL scheme
# =============================================================================

# T5a: the removed v1 hook name is rejected — even with a valid manifest,
# a leaked LTOP_INSTALL_PLATFORM can never steer a production run.
env LTOP_INSTALL_PLATFORM=macos-arm64 LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    sh "$INSTALL" --prefix "$tmp/pfx/t5" --dry-run > "$tmp/out-t5a" 2>&1
expect_rc "T5 removed v1 platform hook exits 1" 1 "$tmp/out-t5a" $?
expect_grep "T5 names the removed hook" "$tmp/out-t5a" 'removed v1 test hook'

# T5b: the test-only hook without a manifest is rejected (a leaked
# platform variable alone must not select a different architecture).
env LTOP_INSTALL_TEST_PLATFORM=macos-arm64 \
    sh "$INSTALL" --prefix "$tmp/pfx/t5" --dry-run > "$tmp/out-t5b" 2>&1
expect_rc "T5 test platform without manifest exits 1" 1 "$tmp/out-t5b" $?
expect_grep "T5 demands the test manifest" "$tmp/out-t5b" 'requires LTOP_INSTALL_TEST_MANIFEST'

# T5c: an invalid platform value is rejected (with a manifest).
env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-aarch64 \
    sh "$INSTALL" --prefix "$tmp/pfx/t5" > "$tmp/out-t5c" 2>&1
expect_rc "T5 invalid test platform exits 1" 1 "$tmp/out-t5c" $?
expect_grep "T5 names the invalid platform" "$tmp/out-t5c" 'invalid LTOP_INSTALL_TEST_PLATFORM'

# T5d: non-http(s) base URL is rejected.
env LTOP_RELEASE_BASE_URL='ftp://127.0.0.1:1' \
    sh "$INSTALL" --prefix "$tmp/pfx/t5" > "$tmp/out-t5d" 2>&1
expect_rc "T5 non-http(s) base URL exits 1" 1 "$tmp/out-t5d" $?
expect_grep "T5 names the invalid base URL" "$tmp/out-t5d" 'invalid base URL'

# =============================================================================
# T6: dry-run changes nothing and reports the existing-target state (F6)
# =============================================================================

run_inst t6 linux-x86_64 "$tmp/pfx/t6" --dry-run
expect_rc "T6 dry-run exits 0" 0 "$tmp/out-t6" "$RC"
expect_grep "T6 dry-run announces no changes" "$tmp/out-t6" 'dry-run: no changes made'
expect_grep "T6 dry-run reports an absent target" "$tmp/out-t6" 'does not exist yet'
if [ ! -e "$tmp/pfx/t6" ]; then
    pass "T6 dry-run created no files"
else
    fail "T6 dry-run created no files" "prefix dir exists after dry-run"
fi

# (T6x: dry-run state resolution against existing targets — see after T8)

# =============================================================================
# T7: install (fixture) — download, verify, atomic install
# =============================================================================

run_inst t7 linux-x86_64 "$tmp/pfx/t7"
expect_rc "T7 install exits 0" 0 "$tmp/out-t7" "$RC"
expect_grep "T7 reports installed" "$tmp/out-t7" 'installed ltop v9.9.9'
expect_grep "T7 shows the license link" "$tmp/out-t7" 'LICENSE.md'
if [ -f "$tmp/pfx/t7/ltop" ]; then
    pass "T7 target exists"
else
    fail "T7 target exists"
fi
if [ "$(sha256_of "$tmp/pfx/t7/ltop" 2>/dev/null)" = "$(sha256_of "$tmp/binfix/ltop-v9.9.9-linux-x86_64/ltop")" ]; then
    pass "T7 target hash matches the fixture binary"
else
    fail "T7 target hash matches the fixture binary"
fi
if [ -x "$tmp/pfx/t7/ltop" ]; then
    pass "T7 target is executable"
else
    fail "T7 target is executable"
fi
if "$tmp/pfx/t7/ltop" | grep -q 'ltop 9.9.9 linux-x86_64'; then
    pass "T7 installed binary runs"
else
    fail "T7 installed binary runs"
fi
# no staging temp files left in the prefix
leftover=$(ls -a "$tmp/pfx/t7" | grep -c '^\.ltop-install\.' || true)
if [ "$leftover" = "0" ]; then
    pass "T7 no temp files left in the prefix"
else
    fail "T7 no temp files left in the prefix" "leftover staging files"
fi

# =============================================================================
# T8: idempotency
# =============================================================================

run_inst t8 linux-x86_64 "$tmp/pfx/t7"
expect_rc "T8 re-run exits 0" 0 "$tmp/out-t8" "$RC"
expect_grep "T8 reports already installed" "$tmp/out-t8" 'already installed'
if [ "$(sha256_of "$tmp/pfx/t7/ltop")" = "$(sha256_of "$tmp/binfix/ltop-v9.9.9-linux-x86_64/ltop")" ]; then
    pass "T8 target unchanged"
else
    fail "T8 target unchanged"
fi

# =============================================================================
# T6x: dry-run state resolution against existing targets (F6)
#
# The dry-run plan must say what a real run would do, and it must never
# prompt (stdin is /dev/null throughout: a prompt read would hang or
# consume the wrong input).
# =============================================================================

run_inst t6x linux-x86_64 "$tmp/pfx/t6x"
expect_rc "T6x install for dry-run state exits 0" 0 "$tmp/out-t6x" "$RC"

env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" \
    --prefix "$tmp/pfx/t6x" --dry-run < /dev/null > "$tmp/out-t6x1" 2>&1
expect_rc "T6x dry-run on the expected binary exits 0" 0 "$tmp/out-t6x1" $?
expect_grep "T6x dry-run reports the no-op" "$tmp/out-t6x1" 'already holds the expected'

printf 'not ltop\n' > "$tmp/pfx/t6x/ltop"
t6x_foreign=$(sha256_of "$tmp/pfx/t6x/ltop")
env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" \
    --prefix "$tmp/pfx/t6x" --dry-run < /dev/null > "$tmp/out-t6x2" 2>&1
expect_rc "T6x dry-run on a foreign file exits 0" 0 "$tmp/out-t6x2" $?
expect_grep "T6x dry-run reports the refusal" "$tmp/out-t6x2" 'a real run would stop here'
if [ "$(sha256_of "$tmp/pfx/t6x/ltop")" = "$t6x_foreign" ]; then
    pass "T6x dry-run left the foreign file untouched"
else
    fail "T6x dry-run left the foreign file untouched"
fi

env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" \
    --prefix "$tmp/pfx/t6x" --dry-run --force < /dev/null > "$tmp/out-t6x3" 2>&1
expect_rc "T6x dry-run --force on a foreign file exits 0" 0 "$tmp/out-t6x3" $?
expect_grep "T6x dry-run reports the forced replacement" "$tmp/out-t6x3" 'would replace the existing file'
if [ "$(sha256_of "$tmp/pfx/t6x/ltop")" = "$t6x_foreign" ]; then
    pass "T6x dry-run --force left the file untouched"
else
    fail "T6x dry-run --force left the file untouched"
fi

rm -f "$tmp/pfx/t6x/ltop"
ln -s /bin/ls "$tmp/pfx/t6x/ltop"
env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" \
    --prefix "$tmp/pfx/t6x" --dry-run < /dev/null > "$tmp/out-t6x4" 2>&1
expect_rc "T6x dry-run on a symlink target exits 0" 0 "$tmp/out-t6x4" $?
expect_grep "T6x dry-run names the symlink" "$tmp/out-t6x4" 'target is a symlink'
expect_grep "T6x dry-run reports the symlink refusal" "$tmp/out-t6x4" 'is a symlink (never followed)'
if [ -L "$tmp/pfx/t6x/ltop" ] && [ "$(readlink "$tmp/pfx/t6x/ltop")" = "/bin/ls" ]; then
    pass "T6x dry-run left the symlink untouched"
else
    fail "T6x dry-run left the symlink untouched"
fi

# =============================================================================
# T9: foreign file — non-interactive refusal
# =============================================================================

printf 'not ltop\n' > "$tmp/pfx/t7/ltop"
foreign_sha=$(sha256_of "$tmp/pfx/t7/ltop")
run_inst t9 linux-x86_64 "$tmp/pfx/t7"
expect_rc "T9 foreign file refused non-interactively" 1 "$tmp/out-t9" "$RC"
expect_grep "T9 explains the refusal" "$tmp/out-t9" 'refusing to replace the existing file'
if [ "$(sha256_of "$tmp/pfx/t7/ltop")" = "$foreign_sha" ]; then
    pass "T9 foreign file untouched"
else
    fail "T9 foreign file untouched"
fi

# =============================================================================
# T10: foreign file — interactive decline / acceptance
# =============================================================================

run_inst_interactive t10a n linux-x86_64 "$tmp/pfx/t7"
expect_rc "T10 interactive 'n' aborts" 1 "$tmp/out-t10a" "$RC"
expect_grep "T10 decline message" "$tmp/out-t10a" 'aborted: keeping the existing file'
if [ "$(sha256_of "$tmp/pfx/t7/ltop")" = "$foreign_sha" ]; then
    pass "T10 foreign file untouched after 'n'"
else
    fail "T10 foreign file untouched after 'n'"
fi

run_inst_interactive t10b y linux-x86_64 "$tmp/pfx/t7"
expect_rc "T10 interactive 'y' replaces" 0 "$tmp/out-t10b" "$RC"
if [ "$(sha256_of "$tmp/pfx/t7/ltop")" = "$(sha256_of "$tmp/binfix/ltop-v9.9.9-linux-x86_64/ltop")" ]; then
    pass "T10 target is the fixture binary after 'y'"
else
    fail "T10 target is the fixture binary after 'y'"
fi

# =============================================================================
# T11: --force replaces a foreign file
# =============================================================================

printf 'still not ltop\n' > "$tmp/pfx/t7/ltop"
run_inst t11 linux-x86_64 "$tmp/pfx/t7" --force
expect_rc "T11 --force exits 0" 0 "$tmp/out-t11" "$RC"
if [ "$(sha256_of "$tmp/pfx/t7/ltop")" = "$(sha256_of "$tmp/binfix/ltop-v9.9.9-linux-x86_64/ltop")" ]; then
    pass "T11 --force replaced the foreign file"
else
    fail "T11 --force replaced the foreign file"
fi

# =============================================================================
# T12: older/known ltop (manifest hash, other platform) is recognized
# =============================================================================

cp "$tmp/binfix/ltop-v9.9.9-macos-arm64/ltop" "$tmp/pfx/t7/ltop"
chmod 755 "$tmp/pfx/t7/ltop"
run_inst t12 linux-x86_64 "$tmp/pfx/t7"
expect_rc "T12 known-ltop file refused non-interactively" 1 "$tmp/out-t12" "$RC"
expect_grep "T12 identifies the known ltop" "$tmp/out-t12" 'looks like ltop v9.9.9 macos-arm64 (test manifest)'

# =============================================================================
# T13: symlink at the target
# =============================================================================

rm -f "$tmp/pfx/t7/ltop"
ln -s /bin/ls "$tmp/pfx/t7/ltop"
run_inst t13a linux-x86_64 "$tmp/pfx/t7"
expect_rc "T13 symlink refused non-interactively" 1 "$tmp/out-t13a" "$RC"
if [ -L "$tmp/pfx/t7/ltop" ] && [ "$(readlink "$tmp/pfx/t7/ltop")" = "/bin/ls" ]; then
    pass "T13 symlink untouched"
else
    fail "T13 symlink untouched"
fi

run_inst t13b linux-x86_64 "$tmp/pfx/t7" --force
expect_rc "T13 --force replaces the symlink" 0 "$tmp/out-t13b" "$RC"
if [ -f "$tmp/pfx/t7/ltop" ] && [ ! -L "$tmp/pfx/t7/ltop" ]; then
    pass "T13 target is now a regular file"
else
    fail "T13 target is now a regular file"
fi
if [ -e /bin/ls ]; then
    pass "T13 symlink target (/bin/ls) intact"
else
    fail "T13 symlink target (/bin/ls) intact"
fi

# =============================================================================
# T14: uninstall — known hash
# =============================================================================

run_inst t14 linux-x86_64 "$tmp/pfx/t14"
expect_rc "T14 install for uninstall exits 0" 0 "$tmp/out-t14" "$RC"
run_inst t14u linux-x86_64 "$tmp/pfx/t14" --uninstall
expect_rc "T14 uninstall exits 0" 0 "$tmp/out-t14u" "$RC"
expect_grep "T14 reports removal" "$tmp/out-t14u" 'removed .*ltop'
if [ ! -e "$tmp/pfx/t14/ltop" ]; then
    pass "T14 target removed"
else
    fail "T14 target removed"
fi

# =============================================================================
# T15: uninstall — foreign hash refused
# =============================================================================

printf 'foreign\n' > "$tmp/pfx/t14/ltop"
run_inst t15 linux-x86_64 "$tmp/pfx/t14" --uninstall
expect_rc "T15 foreign uninstall refused" 1 "$tmp/out-t15" "$RC"
expect_grep "T15 explains the refusal" "$tmp/out-t15" 'refusing to uninstall'
if [ -f "$tmp/pfx/t14/ltop" ]; then
    pass "T15 foreign file kept"
else
    fail "T15 foreign file kept"
fi

# =============================================================================
# T16: uninstall — not installed / symlink / dry-run
# =============================================================================

run_inst t16a linux-x86_64 "$tmp/pfx/t16" --uninstall
expect_rc "T16 uninstall when absent exits 0" 0 "$tmp/out-t16a" "$RC"
expect_grep "T16 reports nothing to do" "$tmp/out-t16a" 'not installed'

mkdir -p "$tmp/pfx/t16"
ln -s /bin/ls "$tmp/pfx/t16/ltop"
run_inst t16b linux-x86_64 "$tmp/pfx/t16" --uninstall
expect_rc "T16 symlink uninstall refused" 1 "$tmp/out-t16b" "$RC"
expect_grep "T16 names the symlink" "$tmp/out-t16b" 'is a symlink'
rm -f "$tmp/pfx/t16/ltop"

run_inst t16c linux-x86_64 "$tmp/pfx/t16c"
expect_rc "T16 install for dry-run uninstall exits 0" 0 "$tmp/out-t16c" "$RC"
run_inst t16d linux-x86_64 "$tmp/pfx/t16c" --uninstall --dry-run
expect_rc "T16 dry-run uninstall exits 0" 0 "$tmp/out-t16d" "$RC"
expect_grep "T16 dry-run announces removal" "$tmp/out-t16d" 'would remove'
if [ -f "$tmp/pfx/t16c/ltop" ]; then
    pass "T16 dry-run uninstall kept the file"
else
    fail "T16 dry-run uninstall kept the file"
fi

# =============================================================================
# T17: hash mismatch — corrupted archive (adversarial)
# =============================================================================

# corrupt the served archive (the manifest still carries the original hash)
printf 'CORRUPT' >> "$tmp/docroot/v9.9.9/ltop-v9.9.9-linux-x86_64.tar.gz"
run_inst t17 linux-x86_64 "$tmp/pfx/t17"
expect_rc "T17 corrupted archive refused" 1 "$tmp/out-t17" "$RC"
expect_grep "T17 names the mismatch" "$tmp/out-t17" 'archive hash mismatch'
if [ ! -e "$tmp/pfx/t17/ltop" ]; then
    pass "T17 nothing installed"
else
    fail "T17 nothing installed"
fi
# restore the archives for later tests (rebuild + re-record sums/manifest)
make_archives

# =============================================================================
# T18: SHA256SUMS tampered (adversarial)
# =============================================================================

cp "$tmp/docroot/v9.9.9/SHA256SUMS" "$tmp/sums.bak"
printf 'tampered\n' >> "$tmp/docroot/v9.9.9/SHA256SUMS"
run_inst t18 linux-x86_64 "$tmp/pfx/t18"
expect_rc "T18 tampered SHA256SUMS refused" 1 "$tmp/out-t18" "$RC"
expect_grep "T18 names the mismatch" "$tmp/out-t18" 'SHA256SUMS file hash mismatch'
mv "$tmp/sums.bak" "$tmp/docroot/v9.9.9/SHA256SUMS"

# =============================================================================
# T19: download failure (dead port)
# =============================================================================

env LTOP_RELEASE_BASE_URL="http://127.0.0.1:1" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" --prefix "$tmp/pfx/t19" \
    > "$tmp/out-t19" 2>&1
expect_rc "T19 dead server fails" 1 "$tmp/out-t19" $?
expect_grep "T19 reports the download failure" "$tmp/out-t19" 'download failed'
if [ ! -e "$tmp/pfx/t19/ltop" ]; then
    pass "T19 nothing installed"
else
    fail "T19 nothing installed"
fi

# =============================================================================
# T20: redirect to a foreign host is rejected (adversarial)
# =============================================================================

env LTOP_RELEASE_BASE_URL="http://127.0.0.1:$PORT_R" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" --prefix "$tmp/pfx/t20" \
    > "$tmp/out-t20" 2>&1
expect_rc "T20 foreign-host redirect refused" 1 "$tmp/out-t20" $?
expect_grep "T20 names the unexpected host" "$tmp/out-t20" 'unexpected host'
if [ ! -e "$tmp/pfx/t20/ltop" ]; then
    pass "T20 nothing installed"
else
    fail "T20 nothing installed"
fi

# =============================================================================
# T21: spaces in the prefix
# =============================================================================

run_inst t21 linux-x86_64 "$tmp/prefix dir with spaces/bin"
expect_rc "T21 install into a spaced prefix exits 0" 0 "$tmp/out-t21" "$RC"
if [ -f "$tmp/prefix dir with spaces/bin/ltop" ]; then
    pass "T21 target exists in the spaced prefix"
else
    fail "T21 target exists in the spaced prefix"
fi
run_inst t21u linux-x86_64 "$tmp/prefix dir with spaces/bin" --uninstall
expect_rc "T21 uninstall from the spaced prefix exits 0" 0 "$tmp/out-t21u" "$RC"

# =============================================================================
# T22: PATH hint
# =============================================================================

run_inst t22 macos-x86_64 "$tmp/pfx/t22"
expect_rc "T22 macos-x86_64 fixture install exits 0" 0 "$tmp/out-t22" "$RC"
expect_grep "T22 prints the PATH hint" "$tmp/out-t22" 'is not in your PATH'
expect_grep "T22 states no shell files are modified" "$tmp/out-t22" 'does not modify shell files'

# =============================================================================
# T23: unsafe prefixes rejected
# =============================================================================

# (no platform override: unsafe-prefix rejection is platform-independent
# and must hold for the detected production platform)
env sh "$INSTALL" --prefix / > "$tmp/out-t23a" 2>&1
expect_rc "T23 / prefix refused" 1 "$tmp/out-t23a" $?
expect_grep "T23 names the unsafe prefix" "$tmp/out-t23a" 'refusing unsafe install prefix'

env sh "$INSTALL" --prefix /usr/bin > "$tmp/out-t23b" 2>&1
expect_rc "T23 /usr/bin prefix refused" 1 "$tmp/out-t23b" $?

env sh "$INSTALL" --prefix relative/dir > "$tmp/out-t23c" 2>&1
expect_rc "T23 relative prefix refused" 1 "$tmp/out-t23c" $?
expect_grep "T23 demands an absolute path" "$tmp/out-t23c" 'must be an absolute path'

# =============================================================================
# T24: --quiet suppresses info output
# =============================================================================

run_inst t24 linux-x86_64 "$tmp/pfx/t24" --quiet
expect_rc "T24 quiet install exits 0" 0 "$tmp/out-t24" "$RC"
if [ ! -s "$tmp/out-t24" ]; then
    pass "T24 quiet produces no output"
else
    fail "T24 quiet produces no output" "output was produced" "$tmp/out-t24"
fi

# =============================================================================
# T25: no shell rc mutation
# =============================================================================

rc_files=''
for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv" "$HOME/.bashrc" \
         "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -f "$f" ] && rc_files="$rc_files $f"
done
if [ -z "$rc_files" ]; then
    skip "T25 no rc mutation" "no rc files exist on this host"
else
    (for f in $rc_files; do sha256_of "$f"; done) > "$tmp/rc.before"
    run_inst t25 linux-x86_64 "$tmp/pfx/t25"
    run_inst t25u linux-x86_64 "$tmp/pfx/t25" --uninstall
    (for f in $rc_files; do sha256_of "$f"; done) > "$tmp/rc.after"
    if cmp -s "$tmp/rc.before" "$tmp/rc.after"; then
        pass "T25 shell rc files unmodified"
    else
        fail "T25 shell rc files unmodified" "rc hashes differ"
    fi
fi

# =============================================================================
# T26: workspace cleanup after a failed run
# =============================================================================

ws_before=$(ls -d "${TMPDIR:-/tmp}"/ltop-install.* 2>/dev/null | wc -l | awk '{print $1}')
# force a failure: dead server
env LTOP_RELEASE_BASE_URL="http://127.0.0.1:1" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" --prefix "$tmp/pfx/t26" \
    > "$tmp/out-t26" 2>&1
ws_after=$(ls -d "${TMPDIR:-/tmp}"/ltop-install.* 2>/dev/null | wc -l | awk '{print $1}')
if [ "$ws_before" = "$ws_after" ]; then
    pass "T26 no workspace residue after failure"
else
    fail "T26 no workspace residue after failure" "workspaces: $ws_before -> $ws_after"
fi

# =============================================================================
# T27: wget fallback (skipped with reason when wget is absent)
# =============================================================================

if command -v wget >/dev/null 2>&1; then
    # build a PATH without curl so the installer must use wget
    nocurl="$tmp/nocurl"
    mkdir -p "$nocurl"
    for t in sh awk mktemp tar gzip gunzip unzip sha256sum shasum wget python3 \
             uname readlink rm cp mv chmod mkdir cat sed grep sleep kill ls wc; do
        p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$nocurl/$t"
    done
    env PATH="$nocurl" LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
        LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" --prefix "$tmp/pfx/t27" \
        > "$tmp/out-t27" 2>&1
    expect_rc "T27 wget fallback install exits 0" 0 "$tmp/out-t27" $?
    if [ -f "$tmp/pfx/t27/ltop" ]; then
        pass "T27 wget fallback installed the fixture"
    else
        fail "T27 wget fallback installed the fixture"
    fi
else
    skip "T27 wget fallback" "wget is not installed on this host"
fi

# =============================================================================
# T28: production HTTPS-only default (curl flag present in the script)
# =============================================================================

if grep -q -- "--proto" "$INSTALL" && grep -q -- "--tlsv1.2" "$INSTALL"; then
    pass "T28 script enforces --proto/--tlsv1.2"
else
    fail "T28 script enforces --proto/--tlsv1.2"
fi

# =============================================================================
# T29: piped script (the curl | sh form) is never interactive
# =============================================================================

# $0 is the shell name (no path) when the script is piped, so the interactive
# hook must not apply: a foreign file is refused, an expected binary is an
# idempotent no-op, and stdin (the script text itself) is never consumed by a
# prompt read.
mkdir -p "$tmp/pfx/t29"
printf 'foreign\n' > "$tmp/pfx/t29/ltop"
t29_foreign=$(sha256_of "$tmp/pfx/t29/ltop")
env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 LTOP_INSTALL_INTERACTIVE=1 \
    sh -s -- --prefix "$tmp/pfx/t29" < "$INSTALL" > "$tmp/out-t29a" 2>&1
expect_rc "T29 piped script refuses foreign file" 1 "$tmp/out-t29a" $?
expect_grep "T29 refusal is non-interactive" "$tmp/out-t29a" 'refusing to replace the existing file'
if [ "$(sha256_of "$tmp/pfx/t29/ltop")" = "$t29_foreign" ]; then
    pass "T29 foreign file untouched"
else
    fail "T29 foreign file untouched"
fi

# expected binary in place: idempotent, no prompt read from the pipe
run_inst t29b linux-x86_64 "$tmp/pfx/t29b"
cp "$tmp/pfx/t29b/ltop" "$tmp/pfx/t29/ltop"
env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 LTOP_INSTALL_INTERACTIVE=1 \
    sh -s -- --prefix "$tmp/pfx/t29" < "$INSTALL" > "$tmp/out-t29c" 2>&1
expect_rc "T29 piped script is idempotent on the expected binary" 0 "$tmp/out-t29c" $?
expect_grep "T29 reports already installed" "$tmp/out-t29c" 'already installed'

# =============================================================================
# T30: interrupts clean up and exit with a clear message/code (F1)
# =============================================================================

# Slow fixture server: every request sleeps 4 s so the signal lands
# mid-download.
PORT_S=$(pick_port)
cat > "$tmp/slow_server.py" <<'PY'
import http.server, sys, time, os
port = int(sys.argv[1]); docroot = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(4)
        path = os.path.join(docroot, self.path.lstrip("/"))
        if os.path.isfile(path):
            data = open(path, "rb").read()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
python3 "$tmp/slow_server.py" "$PORT_S" "$tmp/docroot" >/dev/null 2>&1 &
SRV_PIDS="$SRV_PIDS $!"
wait_port "$PORT_S" || { echo "error: slow server did not start" >&2; exit 1; }

# The signal must be sent by a process with the default SIGINT/SIGTERM
# dispositions: a backgrounded shell job inherits SIG_IGN for SIGINT and
# could not trap it. python3 therefore starts the installer in its own
# session (setsid) and signals the whole process group, so the in-flight
# downloader stops too; the installer's trap must then clean up and exit
# 130 (INT) / 143 (TERM) with the interrupted message.
python3 - "$INSTALL" "$PORT_S" "$MANIFEST" "$tmp/pfx/t30" > "$tmp/out-t30" 2>&1 <<'PY'
import glob, os, signal, subprocess, sys, time
install, port, manifest, prefix = sys.argv[1:5]
env = dict(os.environ,
           LTOP_RELEASE_BASE_URL="http://127.0.0.1:" + port,
           LTOP_INSTALL_TEST_MANIFEST=manifest,
           LTOP_INSTALL_TEST_PLATFORM="linux-x86_64")
ws = lambda: set(glob.glob(os.path.join(os.environ.get("TMPDIR", "/tmp"), "ltop-install.*")))
before = ws()
ok = True
for sig, want, tag in ((signal.SIGINT, 130, "INT"), (signal.SIGTERM, 143, "TERM")):
    p = subprocess.Popen(["sh", install, "--prefix", prefix], env=env,
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                         preexec_fn=os.setsid)
    time.sleep(2.5)  # inside the slow download
    os.killpg(p.pid, sig)
    rc = p.wait()
    err = p.stderr.read().decode("utf-8", "replace")
    msg_ok = "interrupted" in err
    print("%s rc=%d want=%d msg=%s" % (tag, rc, want, "OK" if msg_ok else "MISSING"))
    if not msg_ok:
        print("stderr: " + err[-400:])
    if rc != want or not msg_ok:
        ok = False
left = ws() - before
print("residue=%s" % ("NONE" if not left else "LEFT " + ",".join(sorted(left))))
if left:
    ok = False
tgt = os.path.join(prefix, "ltop")
print("target=%s" % ("ABSENT" if not os.path.exists(tgt) else "PRESENT"))
if os.path.exists(tgt):
    ok = False
sys.exit(0 if ok else 1)
PY
expect_rc "T30 SIGINT/SIGTERM interrupted cleanly" 0 "$tmp/out-t30" $?
expect_grep "T30 SIGINT exits 130" "$tmp/out-t30" 'INT rc=130 want=130'
expect_grep "T30 SIGTERM exits 143" "$tmp/out-t30" 'TERM rc=143 want=143'
expect_grep "T30 no workspace residue" "$tmp/out-t30" 'residue=NONE'
expect_grep "T30 no partial install" "$tmp/out-t30" 'target=ABSENT'

# =============================================================================
# T31: sha256 robustness — backslash paths and unreadable files (F2)
# =============================================================================

# T31a: a target whose path contains a backslash. GNU coreutils sha256sum
# escapes such file names and prefixes the digest line with '\', which the
# old "tool <file> | awk '{print $1}'" form would have returned as the
# "hash". The installer must still recognize the expected binary — an
# idempotent no-op, not a refusal.
run_inst t31a linux-x86_64 "$tmp/pfx/t31a"
expect_rc "T31a install for the backslash test exits 0" 0 "$tmp/out-t31a" "$RC"
mkdir -p "$tmp/pfx/bs\\dir"
cp "$tmp/pfx/t31a/ltop" "$tmp/pfx/bs\\dir/ltop"
run_inst t31b linux-x86_64 "$tmp/pfx/bs\\dir"
expect_rc "T31 backslash-path target is an idempotent no-op" 0 "$tmp/out-t31b" "$RC"
expect_grep "T31 reports already installed" "$tmp/out-t31b" 'already installed'
if [ "$(sha256_of "$tmp/pfx/bs\\dir/ltop")" = "$(sha256_of "$tmp/binfix/ltop-v9.9.9-linux-x86_64/ltop")" ]; then
    pass "T31 backslash-path binary untouched"
else
    fail "T31 backslash-path binary untouched"
fi

# T31c: an unreadable existing file must fail the hash (not produce an
# empty one) and be refused non-interactively.
if [ "$(id -u)" = "0" ]; then
    skip "T31 unreadable existing file" "running as root; chmod 000 is still readable"
else
    mkdir -p "$tmp/pfx/t31c"
    printf 'secret\n' > "$tmp/pfx/t31c/ltop"
    chmod 000 "$tmp/pfx/t31c/ltop"
    run_inst t31c linux-x86_64 "$tmp/pfx/t31c"
    expect_rc "T31 unreadable file refused" 1 "$tmp/out-t31c" "$RC"
    expect_grep "T31 names the unreadable file" "$tmp/out-t31c" 'could not be hashed (unreadable?)'
    expect_grep "T31 refusal is non-interactive" "$tmp/out-t31c" 'refusing to replace the existing file'
    chmod 644 "$tmp/pfx/t31c/ltop"
fi

# =============================================================================
# T32: symlinked prefix components (F3)
# =============================================================================

# T32a: a benign alias — the prefix is a symlink into a safe directory.
# The installer resolves it, says so, and installs at the resolved path.
mkdir -p "$tmp/symreal"
ln -s "$tmp/symreal" "$tmp/sym"
run_inst t32a linux-x86_64 "$tmp/sym/bin"
expect_rc "T32 install through a benign symlinked prefix exits 0" 0 "$tmp/out-t32a" "$RC"
expect_grep "T32 announces the resolution" "$tmp/out-t32a" 'resolves to'
if [ -f "$tmp/symreal/bin/ltop" ]; then
    pass "T32 binary installed at the resolved path"
else
    fail "T32 binary installed at the resolved path"
fi

# T32b: an alias into an unsafe system directory — refused. The literal
# prefix is safe; only the canonical path exposes the target.
ln -s /usr/bin "$tmp/evilprefix"
env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" \
    --prefix "$tmp/evilprefix" > "$tmp/out-t32b" 2>&1
expect_rc "T32 symlinked prefix into /usr/bin refused" 1 "$tmp/out-t32b" $?
expect_grep "T32 names the resolved unsafe path" "$tmp/out-t32b" 'resolves to /usr/bin'
if [ ! -e "$tmp/evilprefix/ltop" ] && [ ! -e /usr/bin/ltop ]; then
    pass "T32 nothing written through the alias"
else
    fail "T32 nothing written through the alias"
fi

# T32c: a symlink loop as the prefix — resolution must fail (bounded),
# not hang.
ln -s loop "$tmp/loop"
env LTOP_RELEASE_BASE_URL="$BASE" LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" \
    --prefix "$tmp/loop" > "$tmp/out-t32c" 2>&1
expect_rc "T32 symlink-loop prefix refused" 1 "$tmp/out-t32c" $?
expect_grep "T32 names the unresolvable prefix" "$tmp/out-t32c" 'cannot resolve the install prefix'

# T32d: a symlinked *component* (not just the final element) is resolved.
mkdir -p "$tmp/compreal/deep"
ln -s "$tmp/compreal" "$tmp/compalias"
run_inst t32d linux-x86_64 "$tmp/compalias/deep"
expect_rc "T32 install through a symlinked component exits 0" 0 "$tmp/out-t32d" "$RC"
if [ -f "$tmp/compreal/deep/ltop" ]; then
    pass "T32 binary installed at the resolved component path"
else
    fail "T32 binary installed at the resolved component path"
fi

# =============================================================================
# T33: download hardening — redirect chain, downgrade rejection (F4)
# =============================================================================

# Multi-route redirect server: routes = {path: redirect|file}
PORT_C=$(pick_port)
cat > "$tmp/chain_server.py" <<'PY'
import http.server, sys, json, os
port = int(sys.argv[1])
routes = json.loads(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        r = routes.get(self.path)
        if r is None:
            self.send_response(404); self.end_headers(); return
        if "redirect" in r:
            self.send_response(302)
            self.send_header("Location", r["redirect"])
            self.end_headers()
        else:
            data = open(r["file"], "rb").read()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
ARCH=$tmp/docroot/v9.9.9/ltop-v9.9.9-linux-x86_64.tar.gz
SUMS=$tmp/docroot/v9.9.9/SHA256SUMS
# T33a routes: the archive URL redirects to a *foreign host string*
# (localhost != 127.0.0.1) on an intermediate hop, then to the allowed
# host at a different path. No URL repeats (wget would otherwise abort on
# its own loop detection), and the final URL is allowed — only a chain
# inspection sees the foreign intermediate hop. (v1 checked the final URL
# only and would have accepted this chain; the content hashes would then
# be the only remaining barrier.)
ROUTES_EVIL=$(python3 -c '
import json, sys
print(json.dumps({
    "/v9.9.9/ltop-v9.9.9-linux-x86_64.tar.gz":
        {"redirect": "http://localhost:%s/evil-mid" % sys.argv[1]},
    "/evil-mid":
        {"redirect": "http://127.0.0.1:%s/v9.9.9/real.tar.gz" % sys.argv[1]},
    "/v9.9.9/real.tar.gz": {"file": sys.argv[2]},
}))' "$PORT_C" "$ARCH")
python3 "$tmp/chain_server.py" "$PORT_C" "$ROUTES_EVIL" >/dev/null 2>&1 &
SRV_PIDS="$SRV_PIDS $!"
wait_port "$PORT_C" || { echo "error: chain server did not start" >&2; exit 1; }

if command -v wget >/dev/null 2>&1; then
    # force the wget path (no curl in PATH) so the chain inspection runs
    nocurl="$tmp/nocurl-t33"
    mkdir -p "$nocurl"
    for t in sh awk mktemp tar gzip gunzip unzip sha256sum shasum wget python3 \
             uname readlink rm cp mv chmod mkdir cat sed grep sleep kill ls wc; do
        p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$nocurl/$t"
    done
    env PATH="$nocurl" LTOP_RELEASE_BASE_URL="http://127.0.0.1:$PORT_C" \
        LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
        LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" \
        --prefix "$tmp/pfx/t33a" > "$tmp/out-t33a" 2>&1
    expect_rc "T33 wget: foreign intermediate hop refused" 1 "$tmp/out-t33a" $?
    expect_grep "T33 names the unexpected hop host" "$tmp/out-t33a" "unexpected host"
    if [ ! -e "$tmp/pfx/t33a/ltop" ]; then
        pass "T33 nothing installed after the refused chain"
    else
        fail "T33 nothing installed after the refused chain"
    fi
else
    skip "T33 wget redirect-chain inspection" "wget is not installed on this host (curl enforces the scheme per hop via --proto and checks the final URL; the intermediate-hop host check is wget-specific and documented as a limitation)"
fi

# T33b: a legitimate multi-hop chain on the allowed host (relative hops)
# must succeed — the chain walk must not break normal redirects.
ROUTES_OK=$(python3 -c '
import json, sys
print(json.dumps({
    "/v9.9.9/ltop-v9.9.9-linux-x86_64.tar.gz":
        {"redirect": "/v9.9.9/mid"},
    "/v9.9.9/mid":
        {"redirect": "/v9.9.9/real.tar.gz"},
    "/v9.9.9/real.tar.gz": {"file": sys.argv[1]},
    "/v9.9.9/SHA256SUMS": {"file": sys.argv[2]},
}))' "$ARCH" "$SUMS")
PORT_C2=$(pick_port)
python3 "$tmp/chain_server.py" "$PORT_C2" "$ROUTES_OK" >/dev/null 2>&1 &
SRV_PIDS="$SRV_PIDS $!"
wait_port "$PORT_C2" || { echo "error: chain server 2 did not start" >&2; exit 1; }
env LTOP_RELEASE_BASE_URL="http://127.0.0.1:$PORT_C2" \
    LTOP_INSTALL_TEST_MANIFEST="$MANIFEST" \
    LTOP_INSTALL_TEST_PLATFORM=linux-x86_64 sh "$INSTALL" \
    --prefix "$tmp/pfx/t33b" > "$tmp/out-t33b" 2>&1
expect_rc "T33 multi-hop chain on the allowed host installs" 0 "$tmp/out-t33b" $?
if [ -f "$tmp/pfx/t33b/ltop" ]; then
    pass "T33 target installed through the chain"
else
    fail "T33 target installed through the chain"
fi

# T33c: unit-test check_hop (extracted from install.sh): an HTTPS base
# must reject a non-HTTPS hop (downgrade) and a foreign host, and accept
# a same-host HTTPS hop.
t33c_fns="$tmp/t33c-fns.sh"
for fn in host_of_url scheme_of_url url_join check_hop; do
    awk -v f="$fn" '
        $0 ~ "^" f "\\(\\) \\{" { fnd = 1 }
        fnd { print }
        fnd && $0 == "}" { exit }' "$INSTALL" >> "$t33c_fns"
done
# Each case runs in its own subshell: check_hop calls die (exit 1) on a
# refusal, which must not stop the remaining cases.
t33c_out=$(sh -c '
    . "$1"
    die() { echo "DIE: $1"; exit 1; }
    BASE_URL="https://127.0.0.1"
    ALLOWED_HOSTS="127.0.0.1"
    ( check_hop "https://127.0.0.1/ok" "redirect hop" ) && echo "same-host-https rc=0" || echo "same-host-https rc=$?"
    ( check_hop "http://127.0.0.1/down" "redirect hop" ) && echo "downgrade rc=0" || echo "downgrade rc=$?"
    ( check_hop "https://other.example/x" "final URL" ) && echo "foreign rc=0" || echo "foreign rc=$?"
' _ "$t33c_fns" 2>&1)
if printf '%s' "$t33c_out" | grep -q 'same-host-https rc=0'; then
    pass "T33 check_hop accepts a same-host HTTPS hop"
else
    fail "T33 check_hop accepts a same-host HTTPS hop" "got: $t33c_out"
fi
if printf '%s' "$t33c_out" | grep -q 'DIE: download redirect hop downgraded to non-HTTPS'; then
    pass "T33 check_hop rejects an HTTPS->HTTP downgrade"
else
    fail "T33 check_hop rejects an HTTPS->HTTP downgrade" "got: $t33c_out"
fi
if printf '%s' "$t33c_out" | grep -q 'DIE: download final URL ended at unexpected host'; then
    pass "T33 check_hop rejects a foreign final host"
else
    fail "T33 check_hop rejects a foreign final host" "got: $t33c_out"
fi

# T33d: the no-downgrade flags are wired into the download path.
if grep -q -- "--proto" "$INSTALL" && grep -q -- "=https" "$INSTALL" \
    && grep -q -- "--tlsv1.2" "$INSTALL" \
    && grep -q -- "--https-only" "$INSTALL" \
    && grep -q -- "--secure-protocol=TLSv1_2" "$INSTALL"; then
    pass "T33 script carries the no-downgrade flags"
else
    fail "T33 script carries the no-downgrade flags"
fi

# =============================================================================

echo "---"
echo "test-install: $tests tests, $failed failed, $skipped skipped"
if [ "$failed" -ne 0 ]; then
    exit 1
fi
echo "test-install: all tests PASS"
exit 0
