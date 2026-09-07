#!/bin/sh
# release-check.sh — pre-publish gate for ltop releases (docs/013 §16.1).
#
# Public-safe: this script is read-only with respect to the release
# repository. It never builds, signs, tags, pushes, or uploads anything;
# it only inspects local files and the local git metadata of <repo_root>.
#
# POSIX sh. Requires: git, python3, sha256sum or shasum, unzip (for .zip
# archives), tar (for .tar.gz archives).
#
# Usage:
#   sh release-check.sh <version> <dist_dir> <repo_root> \
#       [cask_path] [component_count] [forbidden_patterns_file]
#
#   <version>                 release version without leading v (e.g. 0.2.0)
#   <dist_dir>                directory holding the built archives
#                             (e.g. dist/v0.2.0)
#   <repo_root>               ltop-release root (a git repository)
#   [cask_path]               live tap cask to mirror-check against
#                             homebrew/Casks/ltop.rb.template (optional)
#   [component_count]         expected SBOM component count (optional)
#   [forbidden_patterns_file] one ERE per line, blank lines and lines
#                             starting with # skipped; added to the
#                             built-in forbidden set (e.g. internal IP
#                             ranges — never hardcoded here) (optional)
#
# Checks (each prints PASS/FAIL; any FAIL -> exit 1, usage error -> exit 2):
#   1. sums        releases/<v>/SHA256SUMS exists and every listed file
#                  exists in <dist_dir> with a matching SHA-256.
#   2. archives    each listed archive has exactly 4 entries
#                  (LICENSE.md, README.txt, THIRD_PARTY_NOTICES.md, the
#                  binary) under one top-level directory; the binary mode
#                  is 0755 on unix targets and carries no exec bit on
#                  windows targets; all entries share one timestamp
#                  (determinism spot-check).
#   3. cask        (only with cask_path) the `cask "ltop" do ... end`
#                  region of homebrew/Casks/ltop.rb.template and the live
#                  cask are byte-identical.
#   4. sbom        sbom/ltop-<v>.cdx.json parses as JSON, specVersion is
#                  1.6, metadata.component.version equals <v>, and (only
#                  with component_count) the component count matches.
#   5. changelog   CHANGELOG.md contains a `## <v> ` section.
#   6. forbidden   no tracked file (git ls-files) matches the built-in
#                  forbidden patterns (machine-local path prefixes, VM
#                  directory names, machine-local report/log file names,
#                  private-key material) nor the patterns from
#                  forbidden_patterns_file; no tracked file name carries a
#                  secret/signing extension.
#   7. tag         git tag v<v> does not exist yet (prevents double-tag;
#                  a published version is immutable — docs/013 I1).
#
# Exit codes: 0 = all executed checks PASS, 1 = one or more FAIL,
#             2 = usage error.

set -u

if [ "$#" -lt 3 ] || [ "$#" -gt 6 ]; then
    echo "usage: sh release-check.sh <version> <dist_dir> <repo_root> \\" >&2
    echo "       [cask_path] [component_count] [forbidden_patterns_file]" >&2
    exit 2
fi

version=$1
dist_dir=$2
repo_root=$3
cask_path=${4:-}
component_count=${5:-}
patterns_file=${6:-}

# --- input validation -------------------------------------------------------

case $version in
    v*) echo "error: <version> must not carry a leading v: $version" >&2; exit 2 ;;
esac
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: invalid version: $version" >&2
    exit 2
fi
if [ ! -d "$dist_dir" ]; then
    echo "error: dist dir not found: $dist_dir" >&2
    exit 2
fi
if [ ! -d "$repo_root" ]; then
    echo "error: repo root not found: $repo_root" >&2
    exit 2
fi
if ! git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: not a git repository: $repo_root" >&2
    exit 2
fi
if [ -n "$cask_path" ] && [ ! -f "$cask_path" ]; then
    echo "error: cask path not found: $cask_path" >&2
    exit 2
fi
if [ -n "$component_count" ] && ! printf '%s' "$component_count" | grep -Eq '^[0-9]+$'; then
    echo "error: component_count must be a non-negative integer: $component_count" >&2
    exit 2
fi
if [ -n "$patterns_file" ] && [ ! -f "$patterns_file" ]; then
    echo "error: patterns file not found: $patterns_file" >&2
    exit 2
fi

# --- helpers ----------------------------------------------------------------

failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

workdir=$(mktemp -d "${TMPDIR:-/tmp}/ltop-release-check.XXXXXX") || exit 2
trap 'rm -rf "$workdir"' EXIT INT TERM

# Pick a sha256 tool (same policy as verify-release.sh).
if command -v sha256sum >/dev/null 2>&1; then
    hash_tool="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    hash_tool="shasum -a 256"
else
    echo "error: neither sha256sum nor shasum found" >&2
    exit 2
fi

sha256_of() {
    # $1 = file path; prints lowercase hex digest
    $hash_tool "$1" | awk '{print tolower($1)}'
}

# Extract the `cask "ltop" do ... end` region of a cask file.
cask_region() {
    sed -n '/^cask "ltop" do$/,/^end$/p' "$1"
}

# stat wrappers: BSD (macOS) and GNU (Linux) syntaxes differ.
if stat -f %m / >/dev/null 2>&1; then
    stat_mode() { stat -f %Lp "$1"; }
    stat_mtime() { stat -f %m "$1"; }
else
    stat_mode() { stat -c %a "$1"; }
    stat_mtime() { stat -c %Y "$1"; }
fi

# =============================================================================
# 1. sums — releases/<v>/SHA256SUMS vs <dist_dir>
# =============================================================================

sums_file="$repo_root/releases/v$version/SHA256SUMS"
sums_list=""
if [ ! -f "$sums_file" ]; then
    fail "sums: $sums_file not found"
else
    # Parse: <64-hex> <space(s) or " *"> <name>. The name is the whole rest
    # of the line (spaces in names are tolerated).
    sums_list=$(sed -n 's/^\([0-9a-fA-F]\{64\}\)[ *]\{1,2\}\(.*\)$/\1 \2/p' "$sums_file")
    if [ -z "$sums_list" ]; then
        fail "sums: no parsable entries in $sums_file"
    fi
fi

sums_ok=1
if [ -n "$sums_list" ]; then
    while read -r expected name; do
        [ -n "$name" ] || continue
        expected=$(printf '%s' "$expected" | tr 'A-F' 'a-f')
        path="$dist_dir/$name"
        if [ ! -f "$path" ]; then
            echo "  sums: NOT-FOUND $name"
            sums_ok=0
            continue
        fi
        actual=$(sha256_of "$path")
        if [ "$actual" != "$expected" ]; then
            echo "  sums: MISMATCH $name (expected $expected, actual $actual)"
            sums_ok=0
        fi
    done <<EOF
$sums_list
EOF
fi
if [ -n "$sums_list" ] && [ "$sums_ok" -eq 1 ]; then
    pass "sums: every file in releases/v$version/SHA256SUMS exists in $dist_dir with a matching SHA-256"
elif [ -n "$sums_list" ]; then
    fail "sums: see MISMATCH/NOT-FOUND lines above"
else
    : # already reported
fi

# =============================================================================
# 2. archives — shape, modes, timestamps
# =============================================================================

archives_ok=1
archive_count=0
if [ -n "$sums_list" ]; then
    while read -r expected name; do
        [ -n "$name" ] || continue
        path="$dist_dir/$name"
        case $name in
            ltop-v$version-*) : ;;
            *)
                echo "  archives: unexpected archive name: $name"
                archives_ok=0
                continue
                ;;
        esac
        target=${name#ltop-v$version-}
        target=${target%.zip}
        target=${target%.tar.gz}
        case $target in
            windows-*) bin=ltop.exe ;;
            *)         bin=ltop ;;
        esac
        if [ ! -f "$path" ]; then
            archives_ok=0
            continue
        fi
        archive_count=$((archive_count + 1))
        top="ltop-v$version-$target"
        want1="$top/LICENSE.md"
        want2="$top/README.txt"
        want3="$top/THIRD_PARTY_NOTICES.md"
        want4="$top/$bin"
        want=$(printf '%s\n%s\n%s\n%s\n' "$want1" "$want2" "$want3" "$want4" | sort)

        # Extract to a scratch dir and check the extracted tree. This is
        # format-agnostic (bsdtar/GNU tar/Info-ZIP listings differ) and
        # verifies the same recorded shape: one top-level directory,
        # exactly 4 files, binary mode, one shared timestamp.
        extract_dir="$workdir/extract-$archive_count"
        mkdir -p "$extract_dir"
        case $name in
            *.tar.gz) tar -xzf "$path" -C "$extract_dir" 2>/dev/null || {
                    echo "  archives: cannot extract $name"
                    archives_ok=0
                    continue
                } ;;
            *.zip) unzip -q "$path" -d "$extract_dir" 2>/dev/null || {
                    echo "  archives: cannot extract $name"
                    archives_ok=0
                    continue
                } ;;
            *)
                echo "  archives: unsupported archive type: $name"
                archives_ok=0
                continue
                ;;
        esac

        dir_count=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
        dir_name=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1 | xargs -n 1 basename 2>/dev/null)
        if [ "$dir_count" -ne 1 ] || [ "$dir_name" != "$top" ]; then
            echo "  archives: $name must contain exactly one top-level directory ($top/)"
            archives_ok=0
            continue
        fi
        got=$(find "$extract_dir" -type f | sed "s|^$extract_dir/||" | sort)
        if [ "$got" != "$want" ]; then
            echo "  archives: $name entry set differs from the recorded shape"
            printf '%s\n' "$got" | sed 's/^/    /'
            archives_ok=0
            continue
        fi
        # binary mode from the extracted file
        bin_mode=$(stat_mode "$extract_dir/$top/$bin")
        case $target in
            windows-*)
                # an octal permission digit carries the exec bit when it
                # is odd; check each digit of the mode
                exec_bit=0
                rest=$bin_mode
                while [ -n "$rest" ]; do
                    p=${rest%"${rest#?}"}
                    rest=${rest#?}
                    case $p in
                        1|3|5|7) exec_bit=1 ;;
                    esac
                done
                if [ "$exec_bit" -ne 0 ]; then
                    echo "  archives: $name binary must not carry an exec bit (mode $bin_mode)"
                    archives_ok=0
                    continue
                fi
                ;;
            *)
                if [ "$bin_mode" != "755" ]; then
                    echo "  archives: $name binary mode is $bin_mode, expected 755"
                    archives_ok=0
                    continue
                fi
                ;;
        esac
        # all 4 files share one mtime (the fixed archive timestamp)
        n_mtimes=1
        first_mtime=""
        find "$extract_dir" -type f > "$workdir/files.$archive_count"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            mtime=$(stat_mtime "$f")
            if [ -z "$first_mtime" ]; then
                first_mtime=$mtime
            elif [ "$mtime" != "$first_mtime" ]; then
                n_mtimes=2
            fi
        done < "$workdir/files.$archive_count"
        if [ "$n_mtimes" -ne 1 ]; then
            echo "  archives: $name entries do not share one timestamp"
            archives_ok=0
            continue
        fi
        rm -rf "$extract_dir"
    done <<EOF
$sums_list
EOF
fi

if [ "$archive_count" -eq 0 ]; then
    fail "archives: no archives listed in releases/v$version/SHA256SUMS"
elif [ "$archives_ok" -eq 1 ]; then
    pass "archives: $archive_count archive(s) match the recorded shape (4 entries, binary mode, single timestamp)"
else
    fail "archives: see detail lines above"
fi

# =============================================================================
# 3. cask — template mirror vs live cask (only with cask_path)
# =============================================================================

if [ -n "$cask_path" ]; then
    template="$repo_root/homebrew/Casks/ltop.rb.template"
    if [ ! -f "$template" ]; then
        fail "cask: template not found: $template"
    else
        cask_region "$cask_path" > "$workdir/cask.live"
        cask_region "$template" > "$workdir/cask.template"
        if cmp -s "$workdir/cask.live" "$workdir/cask.template"; then
            pass "cask: template cask region is byte-identical to $cask_path"
        else
            fail "cask: template cask region differs from $cask_path"
            diff -u "$workdir/cask.live" "$workdir/cask.template" | sed 's/^/    /' | head -40
        fi
    fi
else
    echo "SKIP cask: no cask_path argument"
fi

# =============================================================================
# 4. sbom
# =============================================================================

sbom_file="$repo_root/sbom/ltop-v$version.cdx.json"
if [ ! -f "$sbom_file" ]; then
    fail "sbom: $sbom_file not found"
else
    sbom_out=$(python3 - "$sbom_file" "$version" "$component_count" <<'PYEOF'
import json, sys
path, version, count = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, "r", encoding="utf-8") as f:
        d = json.load(f)
except Exception as e:
    print("ERROR does not parse as JSON: %s" % e)
    sys.exit(0)
errors = []
if d.get("specVersion") != "1.6":
    errors.append("specVersion is %r, expected 1.6" % d.get("specVersion"))
primary = d.get("metadata", {}).get("component", {})
if primary.get("version") != version:
    errors.append("metadata.component.version is %r, expected %s" % (primary.get("version"), version))
comps = d.get("components", [])
if count and len(comps) != int(count):
    errors.append("component count is %d, expected %s" % (len(comps), count))
if errors:
    print("ERROR " + "; ".join(errors))
else:
    print("OK %d components" % len(comps))
PYEOF
)
    case $sbom_out in
        OK*) pass "sbom: $sbom_file — specVersion 1.6, version $version, $sbom_out" ;;
        *)   fail "sbom: $sbom_out" ;;
    esac
fi

# =============================================================================
# 5. changelog
# =============================================================================

changelog="$repo_root/CHANGELOG.md"
if [ ! -f "$changelog" ]; then
    fail "changelog: $changelog not found"
elif grep -q "^## $version " "$changelog"; then
    pass "changelog: CHANGELOG.md contains a '## $version ' section"
else
    fail "changelog: CHANGELOG.md has no '## $version ' section"
fi

# =============================================================================
# 6. forbidden — built-in + file-supplied patterns over the tracked tree
# =============================================================================

# Built-in patterns: safe to hardcode (no internal values). Internal IP
# ranges and other site-specific patterns come from forbidden_patterns_file.
cat > "$workdir/patterns" <<'PATTERNS'
/Users/
C:[\\/]Users[\\/]
ltop-vm
cert-[^ ]*\.json
server-[^ ]*\.log
BEGIN [A-Z ]*PRIVATE KEY
PATTERNS

if [ -n "$patterns_file" ]; then
    sed -n '/^[^#[:space:]]/p' "$patterns_file" >> "$workdir/patterns"
fi

secret_names=$(git -C "$repo_root" ls-files | grep -E '\.(p12|pfx|pem|key|gpg|asc|env)$' || true)
if [ -n "$secret_names" ]; then
    fail "forbidden: tracked file names with secret/signing extensions:"
    printf '%s\n' "$secret_names" | sed 's/^/    /'
else
    forbidden_hits=0
    git -C "$repo_root" ls-files > "$workdir/tracked"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if grep -I -E -q -f "$workdir/patterns" "$repo_root/$f"; then
            echo "  forbidden: $f"
            forbidden_hits=1
        fi
    done < "$workdir/tracked"
    if [ "$forbidden_hits" -eq 0 ]; then
        pass "forbidden: no tracked file matches the built-in or file-supplied forbidden patterns; no secret file names"
    else
        fail "forbidden: see matching file names above"
    fi
fi

# =============================================================================
# 7. tag — v<v> must not exist yet (pre-publish)
# =============================================================================

existing=$(git -C "$repo_root" tag -l "v$version")
if [ -n "$existing" ]; then
    fail "tag: v$version already exists — this version is already published (immutable, docs/013 I1); do not re-run the pre-publish gate for it"
else
    pass "tag: v$version does not exist yet (safe to tag after commit)"
fi

# =============================================================================

echo "---"
if [ "$failures" -eq 0 ]; then
    echo "release-check: all executed checks PASS"
    exit 0
else
    echo "release-check: $failures check(s) FAILED"
    exit 1
fi
