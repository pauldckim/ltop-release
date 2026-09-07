#!/bin/sh
# test-package-release.sh — deterministic tests for scripts/package-release.sh.
#
# Public-safe: builds synthetic fixture inputs (tiny fake binaries with
# real hashes of the fixtures only) under a mktemp directory and asserts
# the helper's timestamp table, packaging shape, determinism and
# PASS/FAIL/exit-code behavior. No network, no build, no access to the
# real release data. The fixture versions are the registered table keys
# (0.1.0/0.1.1/0.1.2) because the timestamp is keyed by version; the
# fixture content and hashes are synthetic, never real release values.
#
# POSIX sh. Requires: python3 (zip entry inspection), tar, unzip,
# sha256sum or shasum.
#
# Usage: sh scripts/tests/test-package-release.sh
# Exit codes: 0 = all tests pass, 1 = at least one test failed.

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
script_dir=$(dirname -- "$here")
PKG="$script_dir/package-release.sh"

[ -f "$PKG" ] || { echo "error: $PKG not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ltop-test-package-release.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

# --- sha256 helper -----------------------------------------------------------

if command -v sha256sum >/dev/null 2>&1; then
    sha256_of() { sha256sum "$1" | awk '{print tolower($1)}'; }
else
    sha256_of() { shasum -a 256 "$1" | awk '{print tolower($1)}'; }
fi

# --- test harness ------------------------------------------------------------

tests=0
failed=0

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

expect_rc() {
    # $1 = name, $2 = wanted rc, $3 = output file, $4 = actual rc
    if [ "$4" -eq "$2" ]; then
        pass "$1"
    else
        fail "$1" "exit $4, wanted $2" "$3"
    fi
}

# --- fixture builders --------------------------------------------------------

# A synthetic repo root with the two required files.
repo_root="$tmp/repo"
mkdir -p "$repo_root"
printf 'synthetic license text\n' > "$repo_root/LICENSE.md"
printf 'synthetic notices text\n' > "$repo_root/THIRD_PARTY_NOTICES.md"

# Synthetic inputs: one target dir per invocation, fake binary content.
make_inputs() {
    # $1 = inputs dir, $2 = target, $3 = binary name, $4 = content
    mkdir -p "$1/$2"
    printf '%s\n' "$4" > "$1/$2/$3"
    chmod 755 "$1/$2/$3"
}

# Write the expected-sums file for one input binary.
make_sums() {
    # $1 = sums file, $2 = target, $3 = binary name, $4 = inputs dir
    h=$(sha256_of "$4/$2/$3")
    printf '%s  %s/%s\n' "$h" "$2" "$3" > "$1"
}

# Zip entry timestamp check: all entries share date_time == (y,m,d,0,0,0).
zip_ts_ok() {
    # $1 = archive, $2 = y, $3 = m, $4 = d
    python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys, zipfile
path, y, m, d = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
want = (y, m, d, 0, 0, 0)
with zipfile.ZipFile(path) as z:
    for i in z.infolist():
        if i.date_time != want:
            print("BAD %s %s" % (i.filename, i.date_time))
            sys.exit(1)
sys.exit(0)
PYEOF
}

# Extracted-file mtime check (UTC epoch of the registered date).
extracted_mtime_ok() {
    # $1 = archive, $2 = kind (zip|targz), $3 = expected epoch (UTC)
    ex="$tmp/mtime-extract"
    rm -rf "$ex"
    mkdir -p "$ex"
    case $2 in
        zip)   unzip -q "$1" -d "$ex" || return 1 ;;
        targz) tar -xzf "$1" -C "$ex" 2>/dev/null || return 1 ;;
    esac
    python3 - "$ex" "$3" <<'PYEOF'
import os, sys
root, want = sys.argv[1], int(sys.argv[2])
bad = []
for dirpath, dirnames, filenames in os.walk(root):
    for f in filenames:
        p = os.path.join(dirpath, f)
        if int(os.stat(p).st_mtime) != want:
            bad.append("%s %d" % (p, int(os.stat(p).st_mtime)))
if bad:
    print("BAD " + " ".join(bad))
    sys.exit(1)
sys.exit(0)
PYEOF
}

# =============================================================================
# T1: syntax
# =============================================================================

sh -n "$PKG" > "$tmp/out-t1" 2>&1
expect_rc "T1 package-release.sh passes sh -n" 0 "$tmp/out-t1" $?

# =============================================================================
# T2: timestamp table — registered versions select the right date
# =============================================================================

# 0.1.1 -> 2026-09-06 (epoch 1788652800 UTC)
make_inputs "$tmp/in-t2a" macos-arm64 ltop "fake 0.1.1 arm64"
make_sums "$tmp/sums-t2a" macos-arm64 ltop "$tmp/in-t2a"
sh "$PKG" 0.1.1 "$tmp/in-t2a" "$repo_root" "$tmp/out-t2a" "$tmp/sums-t2a" > "$tmp/out-t2a.log" 2>&1
expect_rc "T2 0.1.1 packaging exits 0" 0 "$tmp/out-t2a.log" $?
if zip_ts_ok "$tmp/out-t2a/ltop-v0.1.1-macos-arm64.zip" 2026 9 6 > "$tmp/out-t2a.ts" 2>&1; then
    pass "T2 0.1.1 zip entries carry 2026-09-06 00:00:00"
else
    fail "T2 0.1.1 zip entries carry 2026-09-06 00:00:00" "" "$tmp/out-t2a.ts"
fi

# 0.1.2 -> 2026-09-08 (epoch 1788825600 UTC)
make_inputs "$tmp/in-t2b" linux-x86_64 ltop "fake 0.1.2 linux"
make_sums "$tmp/sums-t2b" linux-x86_64 ltop "$tmp/in-t2b"
sh "$PKG" 0.1.2 "$tmp/in-t2b" "$repo_root" "$tmp/out-t2b" "$tmp/sums-t2b" > "$tmp/out-t2b.log" 2>&1
expect_rc "T2 0.1.2 packaging exits 0" 0 "$tmp/out-t2b.log" $?
if extracted_mtime_ok "$tmp/out-t2b/ltop-v0.1.2-linux-x86_64.tar.gz" targz 1788825600 > "$tmp/out-t2b.ts" 2>&1; then
    pass "T2 0.1.2 tar.gz entries carry 2026-09-08 00:00:00 UTC"
else
    fail "T2 0.1.2 tar.gz entries carry 2026-09-08 00:00:00 UTC" "" "$tmp/out-t2b.ts"
fi

# 0.1.0 -> 2026-09-05 (epoch 1788566400 UTC)
make_inputs "$tmp/in-t2c" windows-x86_64 ltop.exe "fake 0.1.0 windows"
make_sums "$tmp/sums-t2c" windows-x86_64 ltop.exe "$tmp/in-t2c"
sh "$PKG" 0.1.0 "$tmp/in-t2c" "$repo_root" "$tmp/out-t2c" "$tmp/sums-t2c" > "$tmp/out-t2c.log" 2>&1
expect_rc "T2 0.1.0 packaging exits 0" 0 "$tmp/out-t2c.log" $?
if zip_ts_ok "$tmp/out-t2c/ltop-v0.1.0-windows-x86_64.zip" 2026 9 5 > "$tmp/out-t2c.ts" 2>&1; then
    pass "T2 0.1.0 zip entries carry 2026-09-05 00:00:00"
else
    fail "T2 0.1.0 zip entries carry 2026-09-05 00:00:00" "" "$tmp/out-t2c.ts"
fi

# =============================================================================
# T3: unknown version is a usage error (exit 2), no stale default
# =============================================================================

make_inputs "$tmp/in-t3" macos-arm64 ltop "fake unknown version"
sh "$PKG" 0.9.9 "$tmp/in-t3" "$repo_root" "$tmp/out-t3" > "$tmp/out-t3.log" 2>&1
expect_rc "T3 unknown version exits 2" 2 "$tmp/out-t3.log" $?
if grep -q 'no registered archive timestamp' "$tmp/out-t3.log"; then
    pass "T3 names the missing timestamp entry"
else
    fail "T3 names the missing timestamp entry" "" "$tmp/out-t3.log"
fi
if [ ! -e "$tmp/out-t3" ]; then
    pass "T3 produces no output for an unknown version"
else
    fail "T3 produces no output for an unknown version" "output exists: $tmp/out-t3"
fi

# =============================================================================
# T4: usage errors (exit 2)
# =============================================================================

sh "$PKG" 0.1.2 "$tmp/in-t3" "$repo_root" > "$tmp/out-t4a" 2>&1
expect_rc "T4 too few arguments exits 2" 2 "$tmp/out-t4a" $?

sh "$PKG" 0.1.2 "$tmp/missing-inputs" "$repo_root" "$tmp/out-t4b" > "$tmp/out-t4b.log" 2>&1
expect_rc "T4 missing inputs dir exits 2" 2 "$tmp/out-t4b.log" $?

# =============================================================================
# T5: unsupported target dir (exit 1)
# =============================================================================

make_inputs "$tmp/in-t5" macos-arm64 ltop "fake"
make_inputs "$tmp/in-t5" freebsd-arm64 ltop "fake"
sh "$PKG" 0.1.2 "$tmp/in-t5" "$repo_root" "$tmp/out-t5" > "$tmp/out-t5.log" 2>&1
expect_rc "T5 unsupported target dir exits 1" 1 "$tmp/out-t5.log" $?
if grep -q 'unsupported target directory: freebsd-arm64' "$tmp/out-t5.log"; then
    pass "T5 names the unsupported target"
else
    fail "T5 names the unsupported target" "" "$tmp/out-t5.log"
fi

# =============================================================================
# T6: missing binary in a supported target dir (exit 1)
# =============================================================================

mkdir -p "$tmp/in-t6/macos-arm64"
sh "$PKG" 0.1.2 "$tmp/in-t6" "$repo_root" "$tmp/out-t6" > "$tmp/out-t6.log" 2>&1
expect_rc "T6 missing binary exits 1" 1 "$tmp/out-t6.log" $?

# =============================================================================
# T7: input hash mismatch (exit 1)
# =============================================================================

make_inputs "$tmp/in-t7" macos-arm64 ltop "fake content"
printf '0000000000000000000000000000000000000000000000000000000000000000  macos-arm64/ltop\n' > "$tmp/sums-t7"
sh "$PKG" 0.1.2 "$tmp/in-t7" "$repo_root" "$tmp/out-t7" "$tmp/sums-t7" > "$tmp/out-t7.log" 2>&1
expect_rc "T7 hash mismatch exits 1" 1 "$tmp/out-t7.log" $?
if grep -q 'input hash mismatch' "$tmp/out-t7.log"; then
    pass "T7 names the mismatch"
else
    fail "T7 names the mismatch" "" "$tmp/out-t7.log"
fi

# =============================================================================
# T8: missing sums entry (exit 1) and missing sums file (exit 2)
# =============================================================================

make_inputs "$tmp/in-t8" macos-arm64 ltop "fake"
printf '1111111111111111111111111111111111111111111111111111111111111111  macos-x86_64/ltop\n' > "$tmp/sums-t8"
sh "$PKG" 0.1.2 "$tmp/in-t8" "$repo_root" "$tmp/out-t8" "$tmp/sums-t8" > "$tmp/out-t8.log" 2>&1
expect_rc "T8 missing sums entry exits 1" 1 "$tmp/out-t8.log" $?

sh "$PKG" 0.1.2 "$tmp/in-t8" "$repo_root" "$tmp/out-t8b" "$tmp/no-such-sums" > "$tmp/out-t8b.log" 2>&1
expect_rc "T8 missing sums file exits 2" 2 "$tmp/out-t8b.log" $?

# =============================================================================
# T9: no supported targets (exit 1)
# =============================================================================

mkdir -p "$tmp/in-t9/empty-target"
sh "$PKG" 0.1.2 "$tmp/in-t9" "$repo_root" "$tmp/out-t9" > "$tmp/out-t9.log" 2>&1
expect_rc "T9 no supported targets exits 1" 1 "$tmp/out-t9.log" $?

# =============================================================================
# T10: full four-target run — names, shape, modes, sums
# =============================================================================

in10="$tmp/in-t10"
make_inputs "$in10" macos-arm64 ltop "fake arm64"
make_inputs "$in10" macos-x86_64 ltop "fake x86_64"
make_inputs "$in10" windows-x86_64 ltop.exe "fake windows"
make_inputs "$in10" linux-x86_64 ltop "fake linux"
: > "$tmp/sums-t10"
for t in macos-arm64 macos-x86_64 windows-x86_64 linux-x86_64; do
    case $t in windows-*) b=ltop.exe ;; *) b=ltop ;; esac
    h=$(sha256_of "$in10/$t/$b")
    printf '%s  %s/%s\n' "$h" "$t" "$b" >> "$tmp/sums-t10"
done

out10="$tmp/out-t10"
sh "$PKG" 0.1.2 "$in10" "$repo_root" "$out10" "$tmp/sums-t10" > "$tmp/out-t10.log" 2>&1
expect_rc "T10 four-target packaging exits 0" 0 "$tmp/out-t10.log" $?

want_files='ltop-v0.1.2-linux-x86_64.tar.gz
ltop-v0.1.2-macos-arm64.zip
ltop-v0.1.2-macos-x86_64.zip
ltop-v0.1.2-windows-x86_64.zip
SHA256SUMS'
got_files=$(ls "$out10" | sort)
if [ "$got_files" = "$want_files" ]; then
    pass "T10 exactly the four expected archives + SHA256SUMS"
else
    fail "T10 exactly the four expected archives + SHA256SUMS" "got: $got_files"
fi

# SHA256SUMS content matches the recomputed archive hashes, in the fixed
# target order.
sums_ok=1
for t in macos-arm64 macos-x86_64 windows-x86_64 linux-x86_64; do
    case $t in
        linux-*) ext=.tar.gz ;;
        *)       ext=.zip ;;
    esac
    a="$out10/ltop-v0.1.2-$t$ext"
    h=$(sha256_of "$a")
    if ! grep -q "^$h  ltop-v0.1.2-$t$ext\$" "$out10/SHA256SUMS"; then
        sums_ok=0
    fi
done
if [ "$sums_ok" -eq 1 ]; then
    pass "T10 SHA256SUMS lines match the archive hashes"
else
    fail "T10 SHA256SUMS lines match the archive hashes" "" "$out10/SHA256SUMS"
fi

# Archive shape: exactly 4 files under one top-level dir; zip entry modes
# (binary 0755 on unix, no exec bit on windows; others 0644).
shape_ok=1
for t in macos-arm64 macos-x86_64 windows-x86_64 linux-x86_64; do
    case $t in
        linux-*) a="$out10/ltop-v0.1.2-$t.tar.gz" ;;
        *)       a="$out10/ltop-v0.1.2-$t.zip" ;;
    esac
    ex="$tmp/ex-t10-$t"
    rm -rf "$ex"
    mkdir -p "$ex"
    case $a in
        *.tar.gz) tar -xzf "$a" -C "$ex" || shape_ok=0 ;;
        *.zip)    unzip -q "$a" -d "$ex" || shape_ok=0 ;;
    esac
    top="ltop-v0.1.2-$t"
    n_dirs=$(find "$ex" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    n_files=$(find "$ex" -type f | wc -l | tr -d ' ')
    if [ "$n_dirs" -ne 1 ] || [ "$n_files" -ne 4 ]; then
        shape_ok=0
    fi
    if [ ! -f "$ex/$top/LICENSE.md" ] || [ ! -f "$ex/$top/README.txt" ] ||
       [ ! -f "$ex/$top/THIRD_PARTY_NOTICES.md" ]; then
        shape_ok=0
    fi
    case $t in
        windows-*) bin=ltop.exe ;;
        *)         bin=ltop ;;
    esac
    if [ ! -f "$ex/$top/$bin" ]; then
        shape_ok=0
    fi
    # zip entry modes from the archive itself (external_attr >> 16)
    case $a in
        *.zip)
            modes_ok=$(python3 - "$a" "$top" "$bin" "$t" <<'PYEOF'
import sys, zipfile
path, top, bin, target = sys.argv[1:5]
is_unix = not target.startswith("windows")
with zipfile.ZipFile(path) as z:
    for i in z.infolist():
        mode = (i.external_attr >> 16) & 0o777
        name = i.filename.rsplit("/", 1)[-1]
        if name == bin:
            want = 0o755 if is_unix else 0o644
            if is_unix and mode != want:
                print("BAD"); break
            if not is_unix and (mode & 0o111):
                print("BAD"); break
        elif mode != 0o644:
            print("BAD"); break
print("OK")
PYEOF
)
            [ "$modes_ok" = "OK" ] || shape_ok=0
            ;;
    esac
    rm -rf "$ex"
done
if [ "$shape_ok" -eq 1 ]; then
    pass "T10 archive shape and entry modes (4 files, 1 top dir, binary/unix 755, windows no exec, others 644)"
else
    fail "T10 archive shape and entry modes" ""
fi

# Extracted binary hashes == input hashes.
extract_ok=1
for t in macos-arm64 macos-x86_64 windows-x86_64 linux-x86_64; do
    case $t in
        linux-*) a="$out10/ltop-v0.1.2-$t.tar.gz" ;;
        *)       a="$out10/ltop-v0.1.2-$t.zip" ;;
    esac
    case $t in
        windows-*) bin=ltop.exe ;;
        *)         bin=ltop ;;
    esac
    ex="$tmp/ex-t10b-$t"
    rm -rf "$ex"
    mkdir -p "$ex"
    case $a in
        *.tar.gz) tar -xzf "$a" -C "$ex" || extract_ok=0 ;;
        *.zip)    unzip -q "$a" -d "$ex" || extract_ok=0 ;;
    esac
    if [ "$(sha256_of "$ex/ltop-v0.1.2-$t/$bin")" != "$(sha256_of "$in10/$t/$bin")" ]; then
        extract_ok=0
    fi
    rm -rf "$ex"
done
if [ "$extract_ok" -eq 1 ]; then
    pass "T10 extracted binary hashes equal the input hashes"
else
    fail "T10 extracted binary hashes equal the input hashes" ""
fi

# =============================================================================
# T11: determinism — a second run is byte-identical
# =============================================================================

out11="$tmp/out-t11"
sh "$PKG" 0.1.2 "$in10" "$repo_root" "$out11" "$tmp/sums-t10" > "$tmp/out-t11.log" 2>&1
det_ok=1
for f in "$out10"/*; do
    b=$(basename "$f")
    if ! cmp -s "$f" "$out11/$b"; then
        det_ok=0
    fi
done
if [ "$det_ok" -eq 1 ]; then
    pass "T11 second packaging run is byte-identical (archives + SHA256SUMS)"
else
    fail "T11 second packaging run is byte-identical" ""
fi

# =============================================================================

echo "---"
echo "test-package-release: $tests tests, $failed failed"
if [ "$failed" -eq 0 ]; then
    exit 0
else
    exit 1
fi
