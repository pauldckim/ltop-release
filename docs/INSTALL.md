# Installing ltop

ltop is a single binary. Installation = verify the archive, extract it, put
the binary on your `PATH`. No installer, no daemon, no service.

Download from the
[v0.1.0 release](https://github.com/pauldckim/ltop-release/releases/tag/v0.1.0)
and **verify the checksum before running anything**
([VERIFY.md](VERIFY.md)).

## macOS (x86_64)

```sh
# 1. Verify the archive (see VERIFY.md for the expected value)
shasum -a 256 ltop-v0.1.0-macos-x86_64.zip

# 2. Extract and install
unzip ltop-v0.1.0-macos-x86_64.zip
install -m 0755 ltop-v0.1.0-macos-x86_64/ltop /usr/local/bin/ltop

# 3. Check
ltop --version
```

**Unsigned binary (0.1.0).** The macOS binary is not Developer-ID signed or
notarized. Depending on how you obtain it, Gatekeeper may block first launch
(e.g. a quarantined download shows "cannot be opened because the developer
cannot be verified"). After verifying the SHA-256 checksum, you can remove
the quarantine attribute for a binary you trust:

```sh
xattr -d com.apple.quarantine /usr/local/bin/ltop   # or: xattr -cr <dir>
```

Or right-click → Open once. Do this only after the checksum matches. A
signed/notarized build is planned; see [DISTRIBUTION.md](DISTRIBUTION.md).

## Windows (x86_64)

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

## Linux (x86_64)

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

Remove the binary (and the extracted folder, if you kept one):

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
