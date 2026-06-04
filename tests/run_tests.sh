#!/usr/bin/env bash
# POSIX mirror of run_tests.ps1 — runs the GdUnit4 suite headless.
#
#   tests/run_tests.sh                                  # whole suite
#   tests/run_tests.sh unit/world                       # one directory
#   tests/run_tests.sh unit/world/test_island_placer.gd # one file
#
# Godot binary: $GODOT_PATH if set, else the project default below.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(dirname "$script_dir")"

godot="${GODOT_PATH:-/c/Users/chris/OneDrive/Desktop/Stuff/Godot_4.6.2/Godot_v4.6.2-stable_win64_console.exe}"
if [ ! -f "$godot" ]; then
    echo "Godot binary not found: $godot" >&2
    echo "Set \$GODOT_PATH to override." >&2
    exit 1
fi

target="${1:-}"
add_args=()
if [ -n "$target" ]; then
    add_args+=(-a "res://tests/${target}")
else
    add_args+=(-a "res://tests/unit" -a "res://tests/integration")
fi

if [ ! -f "$project_root/addons/gdUnit4/runtest.sh" ]; then
    echo "gdUnit4 not installed. Run: tests/install_gdunit4.sh" >&2
    exit 1
fi

cd "$project_root"
set +e
bash addons/gdUnit4/runtest.sh --godot_binary "$godot" "${add_args[@]}" \
    -rd res://tests/.results -c --ignoreHeadlessMode
code=$?
set -e

if [ "$code" -eq 0 ]; then
    echo -e "\nTests passed."
else
    echo -e "\nTests failed (exit $code). Report: tests/.results/"
fi
exit "$code"
