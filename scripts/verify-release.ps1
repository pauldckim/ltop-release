# verify-release.ps1 — verify ltop release archives against a SHA256SUMS file.
#
# Public-safe helper: no build steps, no network, no internal hosts.
# PowerShell 5.1+ (Windows PowerShell or pwsh).
#
# Usage:
#   .\verify-release.ps1 -SumsFile SHA256SUMS
#   .\verify-release.ps1 -SumsFile SHA256SUMS -Files a.zip, b.tar.gz
#
# Path resolution:
#   - Without -Files, the files listed in SHA256SUMS are resolved relative
#     to the directory CONTAINING the SHA256SUMS file, so the script works
#     from any current directory:
#       .\scripts\verify-release.ps1 -SumsFile .\dist\v0.1.0\SHA256SUMS
#   - Names passed via -Files are used as given (relative to the current
#     directory) and must match a name listed in SHA256SUMS.
#
# Exit codes: 0 = all verified, 1 = mismatch or missing file, 2 = usage error.
#
# Usage/missing-sums failures write to stderr explicitly and exit 2; they do
# not rely on Write-Error (which is a terminating error under
# $ErrorActionPreference = 'Stop' and would abort the script with exit code
# 1 before the `exit 2` is reached).

[CmdletBinding()]
param(
    [Parameter()]
    [string] $SumsFile,

    [Parameter()]
    [string[]] $Files
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SumsFile)) {
    [Console]::Error.WriteLine("usage: verify-release.ps1 -SumsFile <SHA256SUMS> [-Files <a.zip,b.tar.gz>]")
    [Console]::Error.WriteLine("error: -SumsFile is required")
    exit 2
}

if (-not (Test-Path -LiteralPath $SumsFile -PathType Leaf)) {
    [Console]::Error.WriteLine("error: sums file not found: $SumsFile")
    exit 2
}

# Directory containing the sums file (artifact paths resolve against this).
# (Not `Split-Path -LiteralPath -Parent`: that combination is not a valid
# parameter set in PowerShell 7, and -LiteralPath does not exist on
# Split-Path in Windows PowerShell 5.1.)
$sumsDir = [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $SumsFile).Path)
if ([string]::IsNullOrEmpty($sumsDir)) {
    $sumsDir = (Get-Location).Path
}

# Parse "HASH  FILENAME" lines (two-space or single-space separator).
$entries = @{}
Get-Content -LiteralPath $SumsFile | ForEach-Object {
    $line = $_
    if ($line -match '^\s*([0-9a-fA-F]{64})\s+(.+?)\s*$') {
        $entries[$Matches[2]] = $Matches[1].ToLower()
    }
}

if ($entries.Count -eq 0) {
    [Console]::Error.WriteLine("error: no checksum entries found in $SumsFile")
    exit 2
}

$explicitFiles = ($null -ne $Files -and $Files.Count -gt 0)
if (-not $explicitFiles) {
    $Files = @($entries.Keys)
}

$status = 0
$checked = 0

foreach ($f in $Files) {
    if (-not $entries.ContainsKey($f)) {
        Write-Host "MISSING-IN-SUMS  $f"
        $status = 1
        continue
    }
    if ($explicitFiles) {
        $path = $f
    }
    else {
        $path = Join-Path $sumsDir $f
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "NOT-FOUND        $f"
        $status = 1
        continue
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
    $expected = $entries[$f]
    $checked++
    if ($actual -ceq $expected) {
        Write-Host "OK               $f"
    }
    else {
        Write-Host "MISMATCH         $f"
        Write-Host "  expected: $expected"
        Write-Host "  actual:   $actual"
        $status = 1
    }
}

if ($checked -eq 0) {
    Write-Warning "no files were checked"
}
exit $status
