# SPDX-License-Identifier: MPL-2.0
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

Write-Host '+ zig build test --summary all'
& zig build test --summary all
exit $LASTEXITCODE
