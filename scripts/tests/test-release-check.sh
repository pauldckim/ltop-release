#!/bin/sh
# test-release-check.sh — deterministic tests for scripts/release-check.sh.
#
# Public-safe: builds a synthetic fixture release tree under a mktemp
# directory (version 9.9.9, fake hashes, no internal values) and asserts
# the helper's PASS/FAIL/exit-code behavior. No network, no build, no
# access to the real release data.
#
# POSIX sh. Requires: git, python3, tar, unzip, sha256sum or shasum.
#
# Usage: sh scripts/tests/test-release-check.sh
# Exit codes: 0 = all tests pass, 1 = at least one test failed.

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
script_dir=$(dirname -- "$here")
release_check="$script_dir/release-check.sh"

[ -f "$release_check" ] || { echo "error: $release_check not found" >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ltop-test-release-check.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

# Fixture root deliberately carries a space in its path: every helper
# invocation must survive it.
fixture_root="$tmp/fixture dir"
mkdir -p "$fixture_root"

# --- sha256 helper -----------------------------------------------------------

if command -v sha256sum >/dev/null 2>&1; then
    sha256_of() { sha256sum "$1" | awk '{print $1}'; }
else
    sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
fi

# --- fixture builders --------------------------------------------------------

# Build a well-formed release archive (4 files, one top-level dir, fixed
# mtime, binary mode 0755) as zip or tar.gz.
make_archive() {
    # $1 = output path, $2 = kind (zip|targz), $3 = top dir name,
    # $4 = binary name
    out=$1
    kind=$2
    top=$3
    binname=$4
    stage=$(mktemp -d "$tmp/stage.XXXXXX") || exit 1
    mkdir -p "$stage/$top"
    printf 'license text\n' > "$stage/$top/LICENSE.md"
    printf 'readme text\n' > "$stage/$top/README.txt"
    printf 'notices text\n' > "$stage/$top/THIRD_PARTY_NOTICES.md"
    printf 'fake binary\n' > "$stage/$top/$binname"
    chmod 755 "$stage/$top/$binname"
    chmod 644 "$stage/$top/LICENSE.md" "$stage/$top/README.txt" "$stage/$top/THIRD_PARTY_NOTICES.md"
    touch -t 202609060000.00 "$stage/$top/LICENSE.md" "$stage/$top/README.txt" \
        "$stage/$top/THIRD_PARTY_NOTICES.md" "$stage/$top/$binname"
    case $kind in
        zip)
            python3 - "$stage" "$out" "$top" "$binname" <<'PYEOF'
import os, sys, zipfile
stage, out, top, binname = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
files = ["LICENSE.md", "README.txt", "THIRD_PARTY_NOTICES.md", binname]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        p = os.path.join(stage, top, f)
        mode = 0o755 if f == binname else 0o644
        zinfo = zipfile.ZipInfo("%s/%s" % (top, f), date_time=(2026, 9, 6, 0, 0, 0))
        zinfo.external_attr = mode << 16
        with open(p, "rb") as fh:
            z.writestr(zinfo, fh.read())
PYEOF
            ;;
        targz)
            (cd "$stage" && tar -czf "$out" "$top")
            ;;
    esac
    rm -rf "$stage"
}

# Build the fixture git repo with a passing 9.9.9 release tree.
build_fixture() {
    # $1 = repo dir
    repo=$1
    mkdir -p "$repo/releases/v9.9.9" "$repo/sbom" "$repo/homebrew/Casks" "$repo/dist/v9.9.9"
    printf '# Changelog\n\n## 9.9.9 — 2026-01-01 (test)\n\ntest entry\n' > "$repo/CHANGELOG.md"
    printf 'dist/\n' > "$repo/.gitignore"
    cat > "$repo/sbom/ltop-v9.9.9.cdx.json" <<'JSON'
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.6",
  "metadata": {
    "component": {"name": "ltop", "version": "9.9.9"}
  },
  "components": [
    {"name": "dep-a", "version": "1.0.0"},
    {"name": "dep-b", "version": "2.0.0"}
  ]
}
JSON
    # cask template + live cask with identical regions
    cat > "$repo/homebrew/Casks/ltop.rb.template" <<'RUBY'
# header comment

cask "ltop" do
  version "9.9.9"
  sha256 "0000000000000000000000000000000000000000000000000000000000000001"
  url "https://example.invalid/ltop-v9.9.9.zip"
end
RUBY
    sed -n '/^cask "ltop" do$/,$p' "$repo/homebrew/Casks/ltop.rb.template" > "$repo/live-cask.rb"

    # archives: one zip (unix target) + one tar.gz (linux target)
    make_archive "$repo/dist/v9.9.9/ltop-v9.9.9-macos-x86_64.zip" zip ltop-v9.9.9-macos-x86_64 ltop
    make_archive "$repo/dist/v9.9.9/ltop-v9.9.9-linux-x86_64.tar.gz" targz ltop-v9.9.9-linux-x86_64 ltop

    # SHA256SUMS over the archives
    (cd "$repo/dist/v9.9.9" &&
        {
            printf '%s  ltop-v9.9.9-linux-x86_64.tar.gz\n' "$(sha256_of ltop-v9.9.9-linux-x86_64.tar.gz)"
            printf '%s  ltop-v9.9.9-macos-x86_64.zip\n' "$(sha256_of ltop-v9.9.9-macos-x86_64.zip)"
        } > "$repo/releases/v9.9.9/SHA256SUMS")

    # git repo (clean, no tags)
    git -C "$repo" init -q
    git -C "$repo" add -A
    git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
}

# --- test harness --------------------------------------------------------------

tests=0
failed=0

# expect_rc <name> <expected_rc> <cmd...>
expect_rc() {
    name=$1
    want=$2
    shift 2
    tests=$((tests + 1))
    "$@" > "$tmp/last.out" 2>&1
    rc=$?
    if [ "$rc" -eq "$want" ]; then
        echo "PASS $name"
    else
        echo "FAIL $name (exit $rc, wanted $want)"
        sed 's/^/    /' "$tmp/last.out" | tail -15
        failed=$((failed + 1))
    fi
}

# expect_grep <name> <pattern> (matches last command output)
expect_grep() {
    name=$1
    pattern=$2
    tests=$((tests + 1))
    if grep -q "$pattern" "$tmp/last.out"; then
        echo "PASS $name"
    else
        echo "FAIL $name (pattern not found: $pattern)"
        sed 's/^/    /' "$tmp/last.out" | tail -15
        failed=$((failed + 1))
    fi
}

# =============================================================================
# T1: passing fixture (zip + tar.gz, cask mirror, sbom count, patterns file)
# =============================================================================

build_fixture "$fixture_root/repo"
printf '# custom internal range (synthetic)\n10\\.99\\.0\\.\n' > "$fixture_root/patterns.txt"

expect_rc "T1 full run exits 0" 0 sh "$release_check" 9.9.9 \
    "$fixture_root/repo/dist/v9.9.9" "$fixture_root/repo" \
    "$fixture_root/repo/live-cask.rb" 2 "$fixture_root/patterns.txt"
expect_grep "T1 sums PASS" 'PASS sums'
expect_grep "T1 archives PASS (2 archives)" 'PASS archives: 2 archive'
expect_grep "T1 cask PASS" 'PASS cask'
expect_grep "T1 sbom PASS" 'PASS sbom'
expect_grep "T1 changelog PASS" 'PASS changelog'
expect_grep "T1 forbidden PASS" 'PASS forbidden'
expect_grep "T1 tag PASS" 'PASS tag'

# =============================================================================
# T2: sums mismatch
# =============================================================================

repo2="$fixture_root/repo-t2"
cp -R "$fixture_root/repo" "$repo2"
# corrupt one recorded hash (64 f's — still parsable, guaranteed to mismatch)
sed 's/^[0-9a-f]\{64\}  ltop-v9.9.9-macos-x86_64.zip$/ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  ltop-v9.9.9-macos-x86_64.zip/' \
    "$repo2/releases/v9.9.9/SHA256SUMS" > "$repo2/sums.new"
mv "$repo2/sums.new" "$repo2/releases/v9.9.9/SHA256SUMS"

expect_rc "T2 mismatched hash exits 1" 1 sh "$release_check" 9.9.9 "$repo2/dist/v9.9.9" "$repo2"
expect_grep "T2 sums FAIL" 'FAIL sums'

# =============================================================================
# T3: archive shape violation (extra file in the archive)
# =============================================================================

repo3="$fixture_root/repo-t3"
cp -R "$fixture_root/repo" "$repo3"
stage3="$tmp/stage-t3"
mkdir -p "$stage3/ltop-v9.9.9-macos-x86_64"
printf 'license text\n' > "$stage3/ltop-v9.9.9-macos-x86_64/LICENSE.md"
printf 'readme text\n' > "$stage3/ltop-v9.9.9-macos-x86_64/README.txt"
printf 'notices text\n' > "$stage3/ltop-v9.9.9-macos-x86_64/THIRD_PARTY_NOTICES.md"
printf 'fake binary\n' > "$stage3/ltop-v9.9.9-macos-x86_64/ltop"
printf 'extra source file\n' > "$stage3/ltop-v9.9.9-macos-x86_64/main.rs"
chmod 755 "$stage3/ltop-v9.9.9-macos-x86_64/ltop"
touch -t 202609060000.00 "$stage3/ltop-v9.9.9-macos-x86_64/"*
python3 - "$stage3" "$repo3/dist/v9.9.9/ltop-v9.9.9-macos-x86_64.zip" <<'PYEOF'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
top = "ltop-v9.9.9-macos-x86_64"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(os.listdir(os.path.join(stage, top))):
        p = os.path.join(stage, top, f)
        mode = 0o755 if f == "ltop" else 0o644
        zinfo = zipfile.ZipInfo("%s/%s" % (top, f), date_time=(2026, 9, 6, 0, 0, 0))
        zinfo.external_attr = mode << 16
        with open(p, "rb") as fh:
            z.writestr(zinfo, fh.read())
PYEOF
rm -rf "$stage3"
# re-record the sums so the sums check passes and the archive check fails
(cd "$repo3/dist/v9.9.9" &&
    {
        printf '%s  ltop-v9.9.9-linux-x86_64.tar.gz\n' "$(sha256_of ltop-v9.9.9-linux-x86_64.tar.gz)"
        printf '%s  ltop-v9.9.9-macos-x86_64.zip\n' "$(sha256_of ltop-v9.9.9-macos-x86_64.zip)"
    } > "$repo3/releases/v9.9.9/SHA256SUMS")

expect_rc "T3 extra archive entry exits 1" 1 sh "$release_check" 9.9.9 "$repo3/dist/v9.9.9" "$repo3"
expect_grep "T3 archives FAIL" 'FAIL archives'
expect_grep "T3 entry set detail" 'entry set differs'

# =============================================================================
# T4: binary mode violation (0644 binary in a unix archive)
# =============================================================================

repo4="$fixture_root/repo-t4"
cp -R "$fixture_root/repo" "$repo4"
stage4="$tmp/stage-t4"
mkdir -p "$stage4/ltop-v9.9.9-macos-x86_64"
printf 'license text\n' > "$stage4/ltop-v9.9.9-macos-x86_64/LICENSE.md"
printf 'readme text\n' > "$stage4/ltop-v9.9.9-macos-x86_64/README.txt"
printf 'notices text\n' > "$stage4/ltop-v9.9.9-macos-x86_64/THIRD_PARTY_NOTICES.md"
printf 'fake binary\n' > "$stage4/ltop-v9.9.9-macos-x86_64/ltop"
chmod 644 "$stage4/ltop-v9.9.9-macos-x86_64/"*
touch -t 202609060000.00 "$stage4/ltop-v9.9.9-macos-x86_64/"*
python3 - "$stage4" "$repo4/dist/v9.9.9/ltop-v9.9.9-macos-x86_64.zip" <<'PYEOF'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
top = "ltop-v9.9.9-macos-x86_64"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(os.listdir(os.path.join(stage, top))):
        p = os.path.join(stage, top, f)
        zinfo = zipfile.ZipInfo("%s/%s" % (top, f), date_time=(2026, 9, 6, 0, 0, 0))
        zinfo.external_attr = 0o644 << 16
        with open(p, "rb") as fh:
            z.writestr(zinfo, fh.read())
PYEOF
rm -rf "$stage4"
(cd "$repo4/dist/v9.9.9" &&
    {
        printf '%s  ltop-v9.9.9-linux-x86_64.tar.gz\n' "$(sha256_of ltop-v9.9.9-linux-x86_64.tar.gz)"
        printf '%s  ltop-v9.9.9-macos-x86_64.zip\n' "$(sha256_of ltop-v9.9.9-macos-x86_64.zip)"
    } > "$repo4/releases/v9.9.9/SHA256SUMS")

expect_rc "T4 non-executable binary exits 1" 1 sh "$release_check" 9.9.9 "$repo4/dist/v9.9.9" "$repo4"
expect_grep "T4 binary mode detail" 'expected 755'

# =============================================================================
# T5: cask region drift
# =============================================================================

repo5="$fixture_root/repo-t5"
cp -R "$fixture_root/repo" "$repo5"
printf 'cask "ltop" do\n  version "8.8.8"\nend\n' > "$repo5/live-cask.rb"

expect_rc "T5 cask drift exits 1" 1 sh "$release_check" 9.9.9 "$repo5/dist/v9.9.9" "$repo5" "$repo5/live-cask.rb"
expect_grep "T5 cask FAIL" 'FAIL cask'

# =============================================================================
# T6: sbom violations (wrong version, wrong count, invalid JSON)
# =============================================================================

repo6="$fixture_root/repo-t6"
cp -R "$fixture_root/repo" "$repo6"
sed 's/"version": "9.9.9"/"version": "8.8.8"/' "$fixture_root/repo/sbom/ltop-v9.9.9.cdx.json" > "$repo6/sbom/ltop-v9.9.9.cdx.json"
expect_rc "T6 wrong sbom version exits 1" 1 sh "$release_check" 9.9.9 "$repo6/dist/v9.9.9" "$repo6"
expect_grep "T6 sbom FAIL version" 'metadata.component.version is .8.8.8.'

repo6b="$fixture_root/repo-t6b"
cp -R "$fixture_root/repo" "$repo6b"
sh "$release_check" 9.9.9 "$repo6b/dist/v9.9.9" "$repo6b" "" 5 > "$tmp/last.out" 2>&1
rc=$?
tests=$((tests + 1))
if [ "$rc" -eq 1 ] && grep -q 'component count is 2, expected 5' "$tmp/last.out"; then
    echo "PASS T6 wrong sbom count exits 1"
else
    echo "FAIL T6 wrong sbom count (exit $rc)"
    sed 's/^/    /' "$tmp/last.out" | tail -10
    failed=$((failed + 1))
fi

repo6c="$fixture_root/repo-t6c"
cp -R "$fixture_root/repo" "$repo6c"
printf 'not json' > "$repo6c/sbom/ltop-v9.9.9.cdx.json"
expect_rc "T6 invalid sbom JSON exits 1" 1 sh "$release_check" 9.9.9 "$repo6c/dist/v9.9.9" "$repo6c"
expect_grep "T6 sbom FAIL json" 'does not parse as JSON'

# =============================================================================
# T7: changelog section missing
# =============================================================================

repo7="$fixture_root/repo-t7"
cp -R "$fixture_root/repo" "$repo7"
printf '# Changelog\n\n## 8.8.8 — 2026-01-01 (test)\n' > "$repo7/CHANGELOG.md"
expect_rc "T7 missing changelog section exits 1" 1 sh "$release_check" 9.9.9 "$repo7/dist/v9.9.9" "$repo7"
expect_grep "T7 changelog FAIL" 'FAIL changelog'

# =============================================================================
# T8: forbidden content (built-in + file-supplied pattern + secret name)
# =============================================================================

repo8="$fixture_root/repo-t8"
cp -R "$fixture_root/repo" "$repo8"
# fixture content is assembled at runtime so the forbidden literal does
# not appear in this (tracked) test file and trip the scan it tests
synthetic_ip="10.99.0"
printf 'internal host note %s.7 here\n' "$synthetic_ip" > "$repo8/notes.txt"
git -C "$repo8" add notes.txt
git -C "$repo8" -c user.name=test -c user.email=test@example.invalid commit -qm notes
expect_rc "T8 file-supplied pattern hit exits 1" 1 sh "$release_check" 9.9.9 "$repo8/dist/v9.9.9" "$repo8" "" "" "$fixture_root/patterns.txt"
expect_grep "T8 forbidden FAIL" 'FAIL forbidden'
expect_grep "T8 forbidden names the file" 'notes.txt'

repo8b="$fixture_root/repo-t8b"
cp -R "$fixture_root/repo" "$repo8b"
keymat='BEGIN RSA PRIV'
keymat="${keymat}ATE KEY"
printf '%s\n' "$keymat" > "$repo8b/leak.txt"
git -C "$repo8b" add leak.txt
git -C "$repo8b" -c user.name=test -c user.email=test@example.invalid commit -qm leak
expect_rc "T8b built-in pattern hit exits 1" 1 sh "$release_check" 9.9.9 "$repo8b/dist/v9.9.9" "$repo8b"
expect_grep "T8b forbidden FAIL" 'FAIL forbidden'

repo8c="$fixture_root/repo-t8c"
cp -R "$fixture_root/repo" "$repo8c"
printf 'x\n' > "$repo8c/cert.pem"
git -C "$repo8c" add cert.pem
git -C "$repo8c" -c user.name=test -c user.email=test@example.invalid commit -qm pem
expect_rc "T8c secret file name exits 1" 1 sh "$release_check" 9.9.9 "$repo8c/dist/v9.9.9" "$repo8c"
expect_grep "T8c forbidden FAIL name" 'secret/signing extensions'

# =============================================================================
# T9: tag hygiene (tag exists -> FAIL; no tag -> PASS)
# =============================================================================

repo9="$fixture_root/repo-t9"
cp -R "$fixture_root/repo" "$repo9"
git -C "$repo9" tag v9.9.9
expect_rc "T9 existing tag exits 1" 1 sh "$release_check" 9.9.9 "$repo9/dist/v9.9.9" "$repo9"
expect_grep "T9 tag FAIL" 'FAIL tag: v9.9.9 already exists'

# =============================================================================
# T10: usage errors (exit 2)
# =============================================================================

expect_rc "T10 too few args" 2 sh "$release_check" 9.9.9 "$fixture_root/repo/dist/v9.9.9"
expect_rc "T10 leading v in version" 2 sh "$release_check" v9.9.9 "$fixture_root/repo/dist/v9.9.9" "$fixture_root/repo"
expect_rc "T10 bad version shape" 2 sh "$release_check" 9.9 "$fixture_root/repo/dist/v9.9.9" "$fixture_root/repo"
expect_rc "T10 missing dist dir" 2 sh "$release_check" 9.9.9 "$fixture_root/nope" "$fixture_root/repo"
expect_rc "T10 missing repo root" 2 sh "$release_check" 9.9.9 "$fixture_root/repo/dist/v9.9.9" "$fixture_root/nope"
expect_rc "T10 bad component count" 2 sh "$release_check" 9.9.9 "$fixture_root/repo/dist/v9.9.9" "$fixture_root/repo" "" abc
expect_rc "T10 missing patterns file" 2 sh "$release_check" 9.9.9 "$fixture_root/repo/dist/v9.9.9" "$fixture_root/repo" "" "" "$fixture_root/nope.txt"
expect_rc "T10 missing cask path" 2 sh "$release_check" 9.9.9 "$fixture_root/repo/dist/v9.9.9" "$fixture_root/repo" "$fixture_root/nope.rb"

# =============================================================================
# T11: missing sums file
# =============================================================================

repo11="$fixture_root/repo-t11"
cp -R "$fixture_root/repo" "$repo11"
rm "$repo11/releases/v9.9.9/SHA256SUMS"
expect_rc "T11 missing sums exits 1" 1 sh "$release_check" 9.9.9 "$repo11/dist/v9.9.9" "$repo11"
expect_grep "T11 sums FAIL" 'FAIL sums'

# =============================================================================

echo "---"
echo "test-release-check: $tests tests, $failed failed"
if [ "$failed" -ne 0 ]; then
    exit 1
fi
echo "test-release-check: all tests PASS"
exit 0
