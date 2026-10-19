# SPDX-License-Identifier: MPL-2.0
# Regenerates the example outputs. The test suite fails when they drift.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

Write-Host '+ zig build'
& zig build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$bin = Join-Path 'zig-out/bin' 'yed2mermaid'

$jobs = @(
    @{ Arguments = @('example/example.graphml', '-o', 'example/example.mmd'); Label = 'example/example.mmd' },
    @{ Arguments = @('--plain', 'example/example.graphml', '-o', 'example/example.plain.mmd'); Label = 'example/example.plain.mmd' },
    @{ Arguments = @('example/palette.graphml', '-o', 'example/palette.mmd'); Label = 'example/palette.mmd' }
)

foreach ($job in $jobs) {
    Write-Host "+ $bin $($job.Arguments -join ' ')"
    & $bin @($job.Arguments)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host 'regenerated example/example.mmd example/example.plain.mmd example/palette.mmd'
