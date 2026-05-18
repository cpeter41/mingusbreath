# PostToolUse hook — parse-checks an edited .gd file with Godot's headless
# --check-only mode. On a parse error it writes the error to stderr and exits
# 2, which surfaces the failure back to Claude. Non-.gd edits and a missing
# Godot binary are no-ops (exit 0), so the hook is safe on any machine.
#
# Godot location: $env:GODOT_PATH if set, else the default below.

$raw = [Console]::In.ReadToEnd()
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$path = $payload.tool_input.file_path
if (-not $path) { exit 0 }
if (-not $path.ToLower().EndsWith('.gd')) { exit 0 }
if (-not (Test-Path -LiteralPath $path)) { exit 0 }

$godot = $env:GODOT_PATH
if (-not $godot) {
    $godot = 'C:\Users\chris\OneDrive\Desktop\Stuff\Godot_4.6.2\Godot_v4.6.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $godot)) { exit 0 }

$proj = $payload.cwd
if (-not $proj) { $proj = $env:CLAUDE_PROJECT_DIR }
if (-not $proj) { exit 0 }

# Run through cmd so its `2>&1` merges stderr at the cmd level. Windows
# PowerShell 5.1 otherwise wraps a native exe's stderr in NativeCommandError
# records, which mangles the captured output.
$line = "`"$godot`" --headless --path `"$proj`" --check-only --script `"$path`" 2>&1"
$text = (& cmd /c $line | Out-String).Trim()
$code = $LASTEXITCODE

if ($code -ne 0) {
    [Console]::Error.WriteLine("GDScript parse check failed: $path")
    [Console]::Error.WriteLine($text)
    exit 2
}
exit 0
