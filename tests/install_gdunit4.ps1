# Installs the pinned GdUnit4 test framework into addons/gdUnit4/.
# GdUnit4 is not vendored in the repo — run this once per checkout (and in CI)
# before running the test suite. Requires `git` on PATH.
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$version = 'v6.1.3'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $projectRoot 'addons\gdUnit4'

if (Test-Path -LiteralPath $dest) {
    if (-not $Force) {
        Write-Host "gdUnit4 already present at $dest. Use -Force to reinstall." -ForegroundColor Yellow
        exit 0
    }
    Remove-Item -Recurse -Force -LiteralPath $dest
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gdunit4_" + [guid]::NewGuid().ToString('N'))
try {
    git clone --depth 1 --branch $version https://github.com/MikeSchulze/gdUnit4.git $tmp
    Copy-Item -Recurse (Join-Path $tmp 'addons\gdUnit4') $dest
    # The addon's own self-test suite is not needed in a consuming project.
    Remove-Item -Recurse -Force (Join-Path $dest 'test') -ErrorAction SilentlyContinue
    Write-Host "Installed gdUnit4 $version to addons\gdUnit4" -ForegroundColor Green
    Write-Host "Now run: godot --headless --path . --import   (refreshes the class cache)"
} finally {
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}
