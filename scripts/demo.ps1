# SPDX-License-Identifier: MPL-2.0
# Regenerates the example outputs, the extracted pictures and the preview pages.
# The test run rewrites the diagrams too; CI fails when the committed copies are
# out of date.
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

Write-Host "+ $bin --images=pictures example/example.graphml -o example/example.images.mmd"
Remove-Item 'example/pictures' -Recurse -Force -ErrorAction SilentlyContinue
& $bin @('--images=pictures', 'example/example.graphml', '-o', 'example/example.images.mmd')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The pages carry their diagram inline so they open straight from the file
# system; `--images` references stay relative and resolve next to the page.
function Write-Page {
    param([string]$Title, [string]$Diagram, [string]$Output)

    $template = Get-Content 'scripts/preview.html' -Raw
    $source = (Get-Content $Diagram -Raw).TrimEnd()
    $escaped = $source.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    $html = $template.Replace('<!--title-->', $Title).Replace('<!--diagram-->', $escaped)
    Set-Content $Output -Value $html -NoNewline
}

Write-Host '+ example/index.html and example/images.html'
Write-Page 'example/example.graphml, rendered by Mermaid from the CDN' `
    'example/example.mmd' 'example/index.html'
Write-Page 'example/example.graphml with --images=pictures, rendered by Mermaid from the CDN' `
    'example/example.images.mmd' 'example/images.html'

Write-Host 'regenerated example/example.mmd example/example.plain.mmd example/palette.mmd'
Write-Host '            example/example.images.mmd example/pictures example/index.html example/images.html'
