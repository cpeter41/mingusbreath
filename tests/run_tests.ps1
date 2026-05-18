# Canonical test entrypoint. Runs the GdUnit4 suite headless and exits with the
# runner's pass/fail code. Agents run this after any change.
#
#   pwsh tests/run_tests.ps1                                  # whole suite
#   pwsh tests/run_tests.ps1 unit/world                       # one directory
#   pwsh tests/run_tests.ps1 unit/world/test_island_placer.gd # one file
#
# Godot binary: $env:GODOT_PATH if set, else the project default below.
[CmdletBinding()]
param([string]$Target = "")

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

$godot = $env:GODOT_PATH
if (-not $godot) {
    $godot = 'C:\Users\chris\OneDrive\Desktop\Stuff\Godot_4.6.2\Godot_v4.6.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $godot)) {
    Write-Error "Godot binary not found: $godot`nSet `$env:GODOT_PATH to override."
    exit 1
}

# Build the -a (add test dir/file) argument list. With no target, scan the
# unit + integration trees; helpers/ and fixtures/ are deliberately excluded.
$addArgs = @()
if ($Target) {
    $addArgs += @('-a', ("res://tests/" + ($Target -replace '\\', '/')))
} else {
    $addArgs += @('-a', 'res://tests/unit')
    $addArgs += @('-a', 'res://tests/integration')
}

$runner = Join-Path $projectRoot 'addons\gdUnit4\runtest.cmd'

Push-Location $projectRoot
try {
    & $runner --godot_binary $godot @addArgs -rd res://tests/.results -c --ignoreHeadlessMode
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($code -eq 0) {
    Write-Host "`nTests passed." -ForegroundColor Green
} else {
    Write-Host "`nTests failed (exit $code). Report: tests/.results/" -ForegroundColor Red
}
exit $code
