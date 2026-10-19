#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Regenerates the example outputs and the preview page. The test run rewrites
# the diagrams too; CI fails when the committed copies are out of date.
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

echo "+ example/index.html from scripts/preview.html and example/example.mmd"
marker=$(grep -n '<!--diagram-->' scripts/preview.html | cut -d: -f1)
{
  head -n "$((marker - 1))" scripts/preview.html
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' example/example.mmd
  tail -n "+$((marker + 1))" scripts/preview.html
} > example/index.html

echo "regenerated example/example.mmd example/example.plain.mmd example/palette.mmd example/index.html"
