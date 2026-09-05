#!/bin/sh
# verify-release.sh — verify ltop release archives against a SHA256SUMS file.
#
# Public-safe helper: no build steps, no network, no internal hosts.
# Works on macOS (shasum) and Linux (sha256sum), POSIX sh.
#
# Usage:
#   sh verify-release.sh SHA256SUMS              # verify every listed file
#   sh verify-release.sh SHA256SUMS a.zip b.tar.gz  # verify only the given files
#
# Path resolution:
#   - With no explicit file arguments, the files listed in SHA256SUMS are
#     resolved relative to the directory CONTAINING the SHA256SUMS file,
#     so the script works from any current directory:
#       sh scripts/verify-release.sh dist/v0.1.0/SHA256SUMS
#   - Explicit file arguments are used as given (relative to the current
#     directory) and must match a name listed in SHA256SUMS.
#
# Exit codes: 0 = all verified, 1 = mismatch or missing file, 2 = usage error.

set -u

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <SHA256SUMS> [file ...]" >&2
    exit 2
fi

sums_file=$1
shift

if [ ! -f "$sums_file" ]; then
    echo "error: sums file not found: $sums_file" >&2
    exit 2
fi

# Directory containing the sums file (artifact paths resolve against this).
sums_dir=$(CDPATH= cd -- "$(dirname -- "$sums_file")" && pwd) || exit 2

# Pick a sha256 tool.
if command -v sha256sum >/dev/null 2>&1; then
    hash_tool="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    hash_tool="shasum -a 256"
else
    echo "error: neither sha256sum nor shasum found" >&2
    exit 2
fi

status=0
checked=0

# Build the list of files to check: explicit args, or every entry in the
# sums file.
if [ "$#" -gt 0 ]; then
    files="$*"
    resolve=arg
else
    # Separator in SHA256SUMS files: two spaces, or " *" (binary indicator).
    files=$(sed -n 's/^[0-9a-fA-F]\{64\}[ *]\{1,2\}\(.*\)$/\1/p' "$sums_file")
    resolve=sumsdir
fi

for f in $files; do
    # Look up the expected hash for this file name in the sums file.
    expected=$(sed -n "s/^\([0-9a-fA-F]\{64\}\)[ *]\{1,2\}$(printf '%s' "$f" | sed 's/[][\\.*^$/]/\\&/g')[[:space:]]*$/\1/p" "$sums_file" | head -n 1)
    if [ -z "$expected" ]; then
        echo "MISSING-IN-SUMS  $f"
        status=1
        continue
    fi
    case $resolve in
        sumsdir) path="$sums_dir/$f" ;;
        *)       path="$f" ;;
    esac
    if [ ! -f "$path" ]; then
        echo "NOT-FOUND        $f"
        status=1
        continue
    fi
    actual=$($hash_tool "$path" | awk '{print tolower($1)}')
    expected=$(printf '%s' "$expected" | tr 'A-F' 'a-f')
    checked=$((checked + 1))
    if [ "$actual" = "$expected" ]; then
        echo "OK               $f"
    else
        echo "MISMATCH         $f"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        status=1
    fi
done

if [ "$checked" -eq 0 ]; then
    echo "warning: no files were checked" >&2
fi
exit "$status"
