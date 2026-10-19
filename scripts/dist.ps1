# SPDX-License-Identifier: MPL-2.0
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

Write-Host '+ zig build dist'
Remove-Item -Recurse -Force zig-out/dist -ErrorAction SilentlyContinue
& zig build dist
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Get-ChildItem zig-out/dist | Format-Table Name, Length
