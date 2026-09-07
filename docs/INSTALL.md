# Installing ltop

ltop is a single binary. Installation = verify the archive, extract it, put
the binary on your `PATH`. No installer, no daemon, no service.

Download from the official release — **macOS from the v0.1.1 release,
Windows and Linux from the
[v0.1.0 release](https://github.com/pauldckim/ltop-release/releases/tag/v0.1.0)**
(0.1.1 is macOS-only) — and **verify the checksum before running anything**
([VERIFY.md](VERIFY.md)).

## One-line installer (macOS + Linux)

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/pauldckim/ltop-release/install-v2/install.sh | sh
```

`install.sh` (repository root, tag-pinned at `install-v2` — the current
installer channel; the previous `install-v1` tag remains published and
immutable) is a POSIX sh script that, for macOS (arm64 and x86_64,
Rosetta-aware) and Linux (x86_64):

1. detects the platform and selects the pinned artifact
   (macOS → v0.1.1, Linux → v0.1.0 — the current release per platform);
2. downloads the archive **over HTTPS only, with no downgrade** (TLS ≥ 1.2;
   `curl` preferred, `wget` fallback; `curl` runs with `--proto '=https'`
   in production, which refuses any redirect hop to a non-HTTPS URL, and
   the `wget` fallback adds `--https-only`/`--secure-protocol=TLSv1_2` on
   builds that support them and inspects every redirect hop it prints) and
   restricts the final URL to the release hosts — in production mode:
   `github.com`, `objects.githubusercontent.com`,
   `release-assets.githubusercontent.com`;
3. verifies **four SHA-256 values embedded in the script** before
   installing anything: the archive, the release `SHA256SUMS` file, the
   archive line inside that file, and the extracted binary;
4. installs **atomically** (temp file in the target directory +
   `chmod 0755` + `mv`) to `$HOME/.local/bin/ltop` by default.

Properties: no sudo, no shell rc mutation, no services, no state. Re-running
is a no-op when the expected binary is already installed (idempotent). A
different existing file (older ltop or foreign) is **refused in
non-interactive mode unless `--force`**; with a terminal attached the
installer asks before replacing. A symlink at the target is never followed
or overwritten without explicit consent. `--uninstall` removes the target
only when its hash matches a known ltop binary (all 0.1.0/0.1.1 macOS and
Linux hashes); foreign files are refused. Unsafe prefixes (`/`, core system
directories) are rejected — and the check runs against the **canonical**
prefix, so a symlinked `--prefix` cannot alias a write into an unsafe
system directory (benign aliases such as `/tmp` → `/private/tmp` on macOS
are resolved and used); unwritable prefixes produce a clear error (no
privilege escalation is attempted). An interrupt (Ctrl-C / SIGTERM) cleans
up the temporary workspace and staged file and exits with a clear
"interrupted" message and code 130/143 — nothing is left half-installed.
`--dry-run` reports the resolved plan, including what a real run would do
about an existing target, without prompting or changing anything.

Options: `--prefix DIR`, `--force`, `--uninstall`, `--dry-run`, `--quiet`,
`--help`.

**macOS (ad-hoc signed):** the installer never removes the
`com.apple.quarantine` attribute. A `curl` download normally arrives
unquarantined, but if the installed binary carries the attribute the
installer prints checksum-first / System Settings → Privacy & Security →
"Open Anyway" guidance instead of touching it.

**License:** by installing you accept the proprietary freeware license
([LICENSE.md](../LICENSE.md)).

> **Review before you pipe.** `curl | sh` executes whatever the URL serves.
> The tag pin makes the script immutable, but the stronger habit is to fetch
> it first, read or hash-verify it ([VERIFY.md](VERIFY.md) carries the
> SHA-256 of the pinned `install.sh`), then run it. Windows is not covered
> by the installer (use the PowerShell steps below).

## macOS (arm64 and x86_64)

### Homebrew (recommended, one line)

```sh
brew install --cask pauldckim/tap/ltop
```

The fully-qualified command does everything: it auto-taps
`pauldckim/tap` (repository `pauldckim/homebrew-tap`) if needed and,
under Homebrew ≥ 6, trusts **only this cask** (cask-scoped entry in
`~/.homebrew/trust.json`, not the whole tap). The cask selects the
archive for your machine — `ltop-v0.1.1-macos-arm64.zip` on Apple
Silicon, `ltop-v0.1.1-macos-x86_64.zip` on Intel — downloads it from the
official release and verifies its SHA-256.

**Blocked first run (ad-hoc signed, not Developer-ID signed).** The 0.1.1
binaries are ad-hoc signed (the arm64 binary must carry at least an
ad-hoc signature to launch on Apple Silicon; the x86_64 binary is ad-hoc
signed for consistency) but are **not** Developer-ID signed or
notarized, and the cask does not remove the macOS quarantine attribute
for you. `brew install` prints the exact steps as caveats: verify the
checksum of the cached download, then either

```sh
xattr -dr com.apple.quarantine "$(brew --prefix)/Caskroom/ltop"   # before first run
```

(works on both architectures: `/usr/local/...` on Intel,
`/opt/homebrew/...` on Apple Silicon) or run `ltop` once (it is
blocked), then open **System Settings → Privacy & Security** and click
**Open Anyway** next to the ltop warning. (If `ltop` was already run
once and blocked, the quarantine removal alone may not be enough — macOS
caches the assessment per path; use System Settings or reboot.)

Uninstall: `brew uninstall --cask ltop` (plus optional
`brew untrust --cask pauldckim/tap/ltop` and `brew untap pauldckim/tap`).

### Manual install

```sh
# Apple Silicon (arm64)
# 1. Verify the archive (see VERIFY.md for the expected value)
shasum -a 256 ltop-v0.1.1-macos-arm64.zip

# 2. Extract and install
unzip ltop-v0.1.1-macos-arm64.zip
install -m 0755 ltop-v0.1.1-macos-arm64/ltop /usr/local/bin/ltop

# 3. Check
ltop --version
```

```sh
# Intel (x86_64)
# 1. Verify the archive (see VERIFY.md for the expected value)
shasum -a 256 ltop-v0.1.1-macos-x86_64.zip

# 2. Extract and install
unzip ltop-v0.1.1-macos-x86_64.zip
install -m 0755 ltop-v0.1.1-macos-x86_64/ltop /usr/local/bin/ltop

# 3. Check
ltop --version
```

**Ad-hoc signed binary (0.1.1).** The macOS binaries are ad-hoc signed
but **not** Developer-ID signed or notarized. Depending on how you obtain
the binary, Gatekeeper may block first launch (e.g. a quarantined
download shows "cannot be opened because the developer cannot be
verified"). After verifying the SHA-256 checksum, you can remove the
quarantine attribute for a binary you trust:

```sh
xattr -d com.apple.quarantine /usr/local/bin/ltop   # or: xattr -cr <dir>
```

Or right-click → Open once. Do this only after the checksum matches. A
Developer-ID signed/notarized build is planned; see
[DISTRIBUTION.md](DISTRIBUTION.md).

## Windows (x86_64) — 0.1.0 (current Windows release)

0.1.1 is macOS-only; the published 0.1.0 Windows artifact remains the
current Windows release.

```powershell
# 1. Verify the archive (see VERIFY.md for the expected value)
(Get-FileHash .\ltop-v0.1.0-windows-x86_64.zip -Algorithm SHA256).Hash

# 2. Extract into the current directory (the archive already contains the
#    single top-level folder ltop-v0.1.0-windows-x86_64)
Expand-Archive .\ltop-v0.1.0-windows-x86_64.zip -DestinationPath .

# 3a. Run from the extracted folder
.\ltop-v0.1.0-windows-x86_64\ltop.exe --version

# 3b. Or add it to your user PATH (PowerShell)
$dir = "$env:LOCALAPPDATA\ltop"
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item .\ltop-v0.1.0-windows-x86_64\ltop.exe $dir
# Read only the USER-scope PATH. Do NOT use $env:Path here: that is the
# combined machine+user PATH of the current process, and writing it back to
# the User scope would copy every system entry into your user PATH.
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$dir*") {
    if ($userPath) { $userPath = "$userPath;$dir" } else { $userPath = $dir }
    [Environment]::SetEnvironmentVariable("Path", $userPath, "User")
}
```

The PATH change applies to **new shells only** — reopen your terminal (or
start a new PowerShell) before `ltop` can be run by name. The current
session's PATH is not updated.

**Unsigned binary (0.1.0).** The Windows binary is not Authenticode-signed;
SmartScreen may show a "Windows protected your PC" prompt for an unknown
publisher. After verifying the SHA-256 checksum, choose *More info* →
*Run anyway* for a binary you trust. A signed build is planned; see
[DISTRIBUTION.md](DISTRIBUTION.md).

## Linux (x86_64) — 0.1.0 (current Linux release)

0.1.1 is macOS-only; the published 0.1.0 Linux artifact remains the
current Linux release.

```sh
# 1. Verify the archive (see VERIFY.md for the expected value)
sha256sum -c <(echo "<sha256>  ltop-v0.1.0-linux-x86_64.tar.gz")
# or verify against the release SHA256SUMS file:
sha256sum -c SHA256SUMS

# 2. Extract and install
tar xzf ltop-v0.1.0-linux-x86_64.tar.gz
install -m 0755 ltop-v0.1.0-linux-x86_64/ltop /usr/local/bin/ltop

# 3. Check
ltop --version
```

The Linux build is dynamically linked against glibc (verified on Rocky
Linux 9.8 / glibc 2.34). Distributions with older glibc may not run it.

## Uninstall

If you used the one-line installer, uninstall it the same way (it removes
only files whose hash matches a known ltop binary):

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/pauldckim/ltop-release/install-v2/install.sh | sh -s -- --uninstall
```

Otherwise, remove the binary (and the extracted folder, if you kept one):

```sh
sudo rm /usr/local/bin/ltop            # macOS / Linux
Remove-Item "$env:LOCALAPPDATA\ltop\ltop.exe"   # Windows
```

If you added the user-scope PATH entry (step 3b above), remove it again in
PowerShell (a new shell is needed for the change to apply):

```powershell
$dir = "$env:LOCALAPPDATA\ltop"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$newPath = ($userPath -split ';' | Where-Object { $_ -ne $dir }) -join ';'
[Environment]::SetEnvironmentVariable("Path", $newPath, "User")
```

ltop keeps no state, configuration or logs of its own.

## Running it

Point ltop at your llama-server (default `http://localhost:8080`):

```sh
ltop                                  # default endpoint
ltop --endpoint http://localhost:8081 # explicit endpoint
```

Start llama-server with `--metrics` if you want the Inference panel to show
token metrics (without it the Inference source is marked *disabled* and the
rest of the dashboard keeps updating).
