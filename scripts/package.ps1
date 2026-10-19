# SPDX-License-Identifier: MPL-2.0
# Builds the release archives consumed by Homebrew, Chocolatey and the GitHub
# release: one tarball per Unix platform and a zip for Windows, plus SHA256SUMS.
#
# Usage: scripts/package.ps1 [version]     (default: git describe)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$version = if ($args.Count -ge 1) { $args[0] } elseif ($env:VERSION) { $env:VERSION } else { (git describe --tags --always --dirty 2>$null) }
if (-not $version) { $version = 'dev' }
$version = $version -replace '^v', ''

Write-Host '+ zig build dist'
Remove-Item -Recurse -Force zig-out/dist -ErrorAction SilentlyContinue
& zig build dist
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = 'dist/packages'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $out -Force | Out-Null

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("yed2mermaid-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null

function Package([string]$os, [string]$arch, [string]$source, [string]$ext) {
    $name = "yed2mermaid-$version-$os-$arch"
    $directory = Join-Path $staging $name
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $binary = if ($os -eq 'windows') { 'yed2mermaid.exe' } else { 'yed2mermaid' }
    Copy-Item -Path $source -Destination (Join-Path $directory $binary)

    if ($ext -eq 'zip') {
        # The executable sits at the archive root for Chocolatey.
        Compress-Archive -Path (Join-Path $directory $binary) -DestinationPath (Join-Path $out "$name.zip") -Force
    } else {
        & tar -czf (Join-Path $out "$name.tar.gz") -C $directory $binary
        if ($LASTEXITCODE -ne 0) { throw "tar failed for $name" }
    }

    Write-Host "  $out/$name.$ext"
}

try {
    Package 'macos' 'arm64' 'zig-out/dist/yed2mermaid-aarch64-macos' 'tar.gz'
    Package 'macos' 'x64' 'zig-out/dist/yed2mermaid-x86_64-macos' 'tar.gz'
    Package 'linux' 'arm64' 'zig-out/dist/yed2mermaid-aarch64-linux-musl' 'tar.gz'
    Package 'linux' 'x64' 'zig-out/dist/yed2mermaid-x86_64-linux-musl' 'tar.gz'
    Package 'windows' 'x64' 'zig-out/dist/yed2mermaid-x86_64-windows.exe' 'zip'
} finally {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}

$lines = foreach ($file in Get-ChildItem $out -File | Where-Object { $_.Name -ne 'SHA256SUMS' } | Sort-Object Name) {
    $hash = (Get-FileHash -Algorithm SHA256 $file.FullName).Hash.ToLower()
    "$hash  $($file.Name)"
}
Set-Content -Path (Join-Path $out 'SHA256SUMS') -Value $lines

Write-Host "packaged $version into $out"
