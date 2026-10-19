#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Regenerates the example outputs, the extracted pictures and the preview pages.
# The test run rewrites the diagrams too; CI fails when the committed copies are
# out of date.
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

echo "+ $bin --images=pictures example/example.graphml -o example/example.images.mmd"
rm -rf example/pictures
"$bin" --images=pictures example/example.graphml -o example/example.images.mmd

# The pages carry their diagram inline so they open straight from the file
# system; `--images` references stay relative and resolve next to the page.
page() {
  local title=$1 diagram=$2 output=$3
  local marker
  marker=$(grep -n '<!--diagram-->' scripts/preview.html | cut -d: -f1)
  {
    head -n "$((marker - 1))" scripts/preview.html | sed "s|<!--title-->|$title|"
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$diagram"
    tail -n "+$((marker + 1))" scripts/preview.html | sed "s|<!--title-->|$title|"
  } > "$output"
}

echo "+ example/index.html and example/images.html"
page 'example/example.graphml, rendered by Mermaid from the CDN' \
  example/example.mmd example/index.html
page 'example/example.graphml with --images=pictures, rendered by Mermaid from the CDN' \
  example/example.images.mmd example/images.html

echo "regenerated example/example.mmd example/example.plain.mmd example/palette.mmd"
echo "           example/example.images.mmd example/pictures example/index.html example/images.html"
