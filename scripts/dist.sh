#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."

echo "+ zig build dist"
rm -rf zig-out/dist
zig build dist

ls -l zig-out/dist
if command -v file >/dev/null 2>&1; then
    file zig-out/dist/*
fi
