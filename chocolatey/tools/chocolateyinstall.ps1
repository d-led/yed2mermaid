# Downloads and installs the yed2mermaid native binary.
# The URL and checksum are substituted by scripts/generate-chocolatey-package.sh.
$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url      = '__URL__'
$checksum = '__SHA256__'

Install-ChocolateyZipPackage -PackageName 'yed2mermaid' -Url "$url" -UnzipLocation "$toolsDir" -Checksum "$checksum" -ChecksumType 'sha256'

# Smoke test: fail fast if the downloaded binary does not run.
& "$toolsDir\yed2mermaid.exe" --version
