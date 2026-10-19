#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Builds the release archives consumed by Homebrew, Chocolatey and the GitHub
# release: one tarball per Unix platform and a zip for Windows, plus SHA256SUMS.
#
# Usage: scripts/package.sh [version]     (default: git describe)
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-${VERSION:-}}"
if [[ -z "${version}" ]]; then
    version="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"
    version="${version#v}"
fi

command -v zip >/dev/null 2>&1 || { echo "zip is required to build the Windows archive" >&2; exit 1; }

echo "+ zig build dist"
rm -rf zig-out/dist
zig build dist

out="dist/packages"
rm -rf "${out}"
mkdir -p "${out}"
staging="$(mktemp -d)"
trap 'rm -rf "${staging}"' EXIT

package() {
    local os="$1" arch="$2" source="$3" ext="$4"
    local name="yed2mermaid-${version}-${os}-${arch}"
    local directory="${staging}/${name}"
    local binary="yed2mermaid"
    if [[ "${os}" == "windows" ]]; then binary="yed2mermaid.exe"; fi

    mkdir -p "${directory}"
    cp "${source}" "${directory}/${binary}"
    chmod +x "${directory}/${binary}"

    if [[ "${ext}" == "zip" ]]; then
        # The executable sits at the archive root: Chocolatey unzips it straight
        # into the package's tools directory.
        (cd "${directory}" && zip -q -X "${OLDPWD}/${out}/${name}.zip" "${binary}")
    else
        tar -czf "${out}/${name}.tar.gz" -C "${directory}" "${binary}"
    fi
    echo "  ${out}/${name}.${ext}"
}

package macos arm64 "zig-out/dist/yed2mermaid-aarch64-macos" tar.gz
package macos x64 "zig-out/dist/yed2mermaid-x86_64-macos" tar.gz
package linux arm64 "zig-out/dist/yed2mermaid-aarch64-linux-musl" tar.gz
package linux x64 "zig-out/dist/yed2mermaid-x86_64-linux-musl" tar.gz
package windows x64 "zig-out/dist/yed2mermaid-x86_64-windows.exe" zip

if command -v sha256sum >/dev/null 2>&1; then
    (cd "${out}" && sha256sum ./* | sed 's| \./| |' > SHA256SUMS)
else
    (cd "${out}" && shasum -a 256 ./* | sed 's| \./| |' > SHA256SUMS)
fi

echo "packaged ${version} into ${out}"
