#!/bin/sh
# package-release.sh — package ltop release archives from PREBUILT binaries.
#
# Public-safe: this script contains no source code, no build steps, no
# build paths and no internal hosts. It only takes already-built,
# already-gated binaries as input and produces the release archives.
#
# Usage:
#   sh package-release.sh <version> <inputs_dir> <repo_root> <out_dir> [expected_sums]
#
#   <version>           release version, e.g. 0.1.0
#   <inputs_dir>        directory with prebuilt binaries, layout:
#                         macos-x86_64/ltop
#                         windows-x86_64/ltop.exe
#                         linux-x86_64/ltop
#                       (only the targets that exist are packaged)
#   <repo_root>         ltop-release root (must contain LICENSE.md and
#                       THIRD_PARTY_NOTICES.md)
#   <out_dir>           output directory for archives + SHA256SUMS
#   [expected_sums]     optional SHA256SUMS of the input binaries; if given,
#                       every input is verified against it BEFORE packaging
#                       and any mismatch aborts the run.
#
# Archive layout (each archive has one top-level directory):
#   ltop-v<ver>-<target>/
#     ltop[.exe]            the binary (executable bit preserved on Unix)
#     LICENSE.md            ltop freeware license
#     THIRD_PARTY_NOTICES.md  third-party component notices
#     README.txt            brief install / version / hash
#
# Determinism: fixed entry order (sorted), fixed timestamps (release date),
# no machine-local metadata. Identical inputs produce identical archives.
#
# Exit codes: 0 = ok, 1 = verification/packaging failure, 2 = usage error.

set -u

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
    echo "usage: $0 <version> <inputs_dir> <repo_root> <out_dir> [expected_sums]" >&2
    exit 2
fi

version=$1
inputs_dir=$2
repo_root=$3
out_dir=$4
expected_sums=${5:-}

# Fixed timestamp for deterministic archives (release date, UTC).
# TS_TOUCH is the touch(1) form of the same instant.
TS_ZIP="2026,9,5,0,0,0"
TS_TOUCH="202609050000.00"

for d in "$inputs_dir" "$repo_root"; do
    if [ ! -d "$d" ]; then
        echo "error: directory not found: $d" >&2
        exit 2
    fi
done
for f in "$repo_root/LICENSE.md" "$repo_root/THIRD_PARTY_NOTICES.md"; do
    if [ ! -f "$f" ]; then
        echo "error: required file not found: $f" >&2
        exit 2
    fi
done

if [ -n "$expected_sums" ]; then
    if [ ! -f "$expected_sums" ]; then
        echo "error: expected sums file not found: $expected_sums" >&2
        exit 2
    fi
    # Verify each input binary against the expected sums (portable lookup).
    for target in macos-x86_64 windows-x86_64 linux-x86_64; do
        case $target in
            windows-x86_64) bin=ltop.exe ;;
            *)              bin=ltop ;;
        esac
        p="$inputs_dir/$target/$bin"
        [ -f "$p" ] || continue
        if command -v sha256sum >/dev/null 2>&1; then
            actual=$(sha256sum "$p" | awk '{print tolower($1)}')
        else
            actual=$(shasum -a 256 "$p" | awk '{print tolower($1)}')
        fi
        # The sums file keys on the target-qualified relative path
        # (e.g. "macos-x86_64/ltop") so same-named binaries per target are
        # distinguished.
        rel="$target/$bin"
        expected=$(sed -n "s/^\([0-9a-fA-F]\{64\}\)[ *]\{1,2\}$(printf '%s' "$rel" | sed 's/[][\\.*^$/]/\\&/g')[[:space:]]*$/\1/p" "$expected_sums" | head -n 1 | tr 'A-F' 'a-f')
        if [ -z "$expected" ]; then
            echo "error: $rel not listed in $expected_sums" >&2
            exit 1
        fi
        if [ "$actual" != "$expected" ]; then
            echo "error: input hash mismatch for $target/$bin" >&2
            echo "  expected: $expected" >&2
            echo "  actual:   $actual" >&2
            exit 1
        fi
        echo "verified input: $target/$bin"
    done
fi

mkdir -p "$out_dir" || exit 1

# sha256 helper (portable).
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print tolower($1)}'
    else
        shasum -a 256 "$1" | awk '{print tolower($1)}'
    fi
}

stage_root=$(mktemp -d) || exit 1
trap 'rm -rf "$stage_root"' EXIT INT TERM

sums_lines=""

for target in macos-x86_64 windows-x86_64 linux-x86_64; do
    case $target in
        windows-x86_64) bin=ltop.exe ;;
        *)              bin=ltop ;;
    esac
    p="$inputs_dir/$target/$bin"
    [ -f "$p" ] || continue

    dir="ltop-v${version}-${target}"
    stage="$stage_root/$dir"
    mkdir -p "$stage" || exit 1
    cp "$p" "$stage/$bin" || exit 1
    cp "$repo_root/LICENSE.md" "$stage/LICENSE.md" || exit 1
    cp "$repo_root/THIRD_PARTY_NOTICES.md" "$stage/THIRD_PARTY_NOTICES.md" || exit 1
    chmod 0755 "$stage/$bin"

    bin_hash=$(sha256_of "$stage/$bin")

    case $target in
        macos-x86_64)
            osline="macOS x86_64 (Intel)"
            extract="unzip ${dir}.zip"
            ;;
        windows-x86_64)
            osline="Windows x86_64"
            extract="Expand-Archive ${dir}.zip"
            ;;
        linux-x86_64)
            osline="Linux x86_64 (glibc)"
            extract="tar xzf ${dir}.tar.gz"
            ;;
    esac

    cat > "$stage/README.txt" <<EOF
ltop v${version} — ${osline}
============================

Contents:
  ${bin}                  the ltop binary (SHA-256: ${bin_hash})
  LICENSE.md              ltop freeware license (proprietary, non-open-source)
  THIRD_PARTY_NOTICES.md  third-party components and their licenses
  README.txt              this file

Install:
  ${extract}
  then put ${bin} on your PATH (see the repository INSTALL.md for details).

Check:
  ${bin} --version        # must print: ltop ${version}

License: proprietary freeware — free to use and to redistribute
unmodified; no sale, no modification, no reverse engineering.
Repository: https://github.com/pauldckim/ltop-release
EOF

    # Deterministic archive.
    archive_abs=$(cd "$out_dir" && pwd)/${dir}
    case $target in
        linux-x86_64)
            archive="${archive_abs}.tar.gz"
            # Portable deterministic tar (GNU tar and bsdtar alike):
            # fixed entry order (find | sort -z), zeroed owner/group,
            # numeric ids, mtimes normalized to the release date (UTC) via
            # touch (bsdtar has no --mtime), gzip -n (no name/timestamp).
            TZ=UTC touch -t "$TS_TOUCH" "$stage_root/$dir" "$stage_root/$dir"/* || exit 1
            (
                cd "$stage_root" || exit 1
                find "$dir" -print0 | LC_ALL=C sort -z |
                    tar --null --no-recursion --owner=0 --group=0 --numeric-owner \
                        -cf - -T - | gzip -n > "$archive"
            ) || exit 1
            ;;
        *)
            archive="${archive_abs}.zip"
            python3 - "$stage_root" "$dir" "$archive" "$TS_ZIP" "$target" <<'PYEOF' || exit 1
import sys, zipfile, os
stage_root, dir, archive, ts, target = sys.argv[1:6]
date = tuple(int(x) for x in ts.split(","))
names = sorted(os.listdir(os.path.join(stage_root, dir)))
is_unix = target != "windows-x86_64"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
    for n in names:
        full = os.path.join(stage_root, dir, n)
        arc = f"{dir}/{n}"
        info = zipfile.ZipInfo(arc, date_time=date)
        info.compress_type = zipfile.ZIP_DEFLATED
        if os.path.isfile(full):
            mode = 0o755 if (is_unix and n.startswith("ltop")) else 0o644
            info.external_attr = (mode << 16)
            with open(full, "rb") as f:
                z.writestr(info, f.read())
        else:
            info.external_attr = (0o755 << 16)
            z.writestr(info, b"")
PYEOF
            ;;
    esac

    arch_hash=$(sha256_of "$archive")
    case $target in
        linux-x86_64) ext=.tar.gz ;;
        *)            ext=.zip ;;
    esac
    sums_lines="${sums_lines}${arch_hash}  ${dir}${ext}
"
    echo "packaged: $(basename "$archive")  sha256=${arch_hash}"
done

if [ -z "$sums_lines" ]; then
    echo "error: no targets found under $inputs_dir" >&2
    exit 1
fi

printf '%s' "$sums_lines" > "$out_dir/SHA256SUMS"
echo "wrote: $out_dir/SHA256SUMS"
