#!/usr/bin/env bash
# POSIX mirror of install_gdunit4.ps1 — installs the pinned GdUnit4 framework
# into addons/gdUnit4/. Run once per checkout before running the test suite.
set -euo pipefail

version="v6.1.3"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(dirname "$script_dir")"
dest="$project_root/addons/gdUnit4"

if [ -d "$dest" ]; then
    if [ "${1:-}" != "--force" ]; then
        echo "gdUnit4 already present at $dest. Pass --force to reinstall."
        exit 0
    fi
    rm -rf "$dest"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone --depth 1 --branch "$version" https://github.com/MikeSchulze/gdUnit4.git "$tmp"
mkdir -p "$project_root/addons"
cp -r "$tmp/addons/gdUnit4" "$dest"
# The addon's own self-test suite is not needed in a consuming project.
rm -rf "$dest/test"
echo "Installed gdUnit4 $version to addons/gdUnit4"
echo "Now run: godot --headless --path . --import   (refreshes the class cache)"
