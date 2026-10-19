# SPDX-License-Identifier: MPL-2.0
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

Write-Host '+ zig build -Doptimize=ReleaseSmall'
& zig build -Doptimize=ReleaseSmall
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Get-Item zig-out/bin/yed2mermaid* | Format-Table Name, Length
