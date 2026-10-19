# SPDX-License-Identifier: MPL-2.0
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

Write-Host '+ zig fmt --check build.zig src'
& zig fmt --check build.zig src
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'formatting is clean'
