# SPDX-License-Identifier: MPL-2.0
# Generates the Chocolatey package for yed2mermaid from chocolatey/ templates.
# Expects VERSION, URL and SHA256. Packs the .nupkg when choco is available.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$version = $env:VERSION
$url = $env:URL
$sha256 = $env:SHA256
$outdir = if ($env:OUTDIR) { $env:OUTDIR } else { 'dist/choco' }

if (-not $version) { throw 'VERSION is required' }
if (-not $url) { throw 'URL is required' }
if (-not $sha256) { throw 'SHA256 is required' }

$releaseUrl = "https://github.com/d-led/yed2mermaid/releases/tag/v$version"
New-Item -ItemType Directory -Path (Join-Path $outdir 'tools') -Force | Out-Null

$nuspec = Get-Content 'chocolatey/yed2mermaid.nuspec' -Raw
$nuspec = $nuspec.Replace('__VERSION__', $version).Replace('__URL__', $url).Replace('__SHA256__', $sha256).Replace('__RELEASE_URL__', $releaseUrl)
Set-Content -Path (Join-Path $outdir 'yed2mermaid.nuspec') -Value $nuspec -NoNewline

$install = Get-Content 'chocolatey/tools/chocolateyinstall.ps1' -Raw
$install = $install.Replace('__URL__', $url).Replace('__SHA256__', $sha256)
Set-Content -Path (Join-Path $outdir 'tools/chocolateyinstall.ps1') -Value $install -NoNewline

Copy-Item 'chocolatey/tools/chocolateyuninstall.ps1' (Join-Path $outdir 'tools/chocolateyuninstall.ps1') -Force
Copy-Item 'LICENSE' (Join-Path $outdir 'LICENSE.txt') -Force

if (Get-Command choco -ErrorAction SilentlyContinue) {
    & choco pack (Join-Path $outdir 'yed2mermaid.nuspec') --outputdirectory $outdir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host "choco is not on PATH; templates written to $outdir"
    Write-Host "pack on Windows with: choco pack $outdir/yed2mermaid.nuspec --outputdirectory $outdir"
}
