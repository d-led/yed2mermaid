#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Regenerates the example outputs. The test suite fails when they drift.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "+ zig build"
zig build
bin=./zig-out/bin/yed2mermaid

echo "+ $bin example/example.graphml -o example/example.mmd"
"$bin" example/example.graphml -o example/example.mmd

echo "+ $bin --plain example/example.graphml -o example/example.plain.mmd"
"$bin" --plain example/example.graphml -o example/example.plain.mmd

echo "+ $bin example/palette.graphml -o example/palette.mmd"
"$bin" example/palette.graphml -o example/palette.mmd

echo "regenerated example/example.mmd example/example.plain.mmd example/palette.mmd"
