#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Generates the Chocolatey package for yed2mermaid from the templates in
# chocolatey/ and the given version/URL/checksum.
#
# Expects the following environment variables:
#   VERSION   e.g. 1.2.3
#   URL       direct download URL of the Windows zip
#   SHA256    sha256 of that zip
#
# When Chocolatey (choco) is on PATH the .nupkg is packed; otherwise the
# substituted templates are left in OUTDIR for packing on Windows.
#
# Usage:
#   VERSION=1.2.3 URL=... SHA256=... scripts/generate-chocolatey-package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

version="${VERSION:?VERSION is required}"
url="${URL:?URL is required}"
sha256="${SHA256:?SHA256 is required}"
outdir="${OUTDIR:-dist/choco}"
release_url="https://github.com/d-led/yed2mermaid/releases/tag/v${version}"

mkdir -p "${outdir}/tools"

sed \
    -e "s|__VERSION__|${version}|g" \
    -e "s|__URL__|${url}|g" \
    -e "s|__SHA256__|${sha256}|g" \
    -e "s|__RELEASE_URL__|${release_url}|g" \
    chocolatey/yed2mermaid.nuspec > "${outdir}/yed2mermaid.nuspec"

sed "s|__URL__|${url}|g; s|__SHA256__|${sha256}|g" \
    chocolatey/tools/chocolateyinstall.ps1 > "${outdir}/tools/chocolateyinstall.ps1"

cp chocolatey/tools/chocolateyuninstall.ps1 "${outdir}/tools/chocolateyuninstall.ps1"
cp LICENSE "${outdir}/LICENSE.txt"

if command -v choco >/dev/null 2>&1; then
    choco pack "${outdir}/yed2mermaid.nuspec" --outputdirectory "${outdir}"
else
    echo "choco is not on PATH; templates written to ${outdir}"
    echo "pack on Windows with: choco pack ${outdir}/yed2mermaid.nuspec --outputdirectory ${outdir}"
fi
