# Publishing

Back to the [README](../README.md).

## Continuous integration

`.github/workflows/ci.yml` checks formatting, runs the test suite (its summary
is written to the run page), regenerates the example outputs through the CLI and
fails when the committed ones are out of date, then builds the release binaries
and uploads them as build artifacts.

## Release

`.github/workflows/release.yml` runs for `v*.*.*` tags, and can be dispatched
for an existing version (`gh workflow run release.yml -f version=0.2.0`) so a
release can be rebuilt without moving a protected tag. It tests, builds the
archives, publishes them with `SHA256SUMS` and the generated Homebrew formula,
then updates the tap and the Chocolatey package when the credentials are
configured.

| Secret | Used for |
|---|---|
| `PUBLISHER_TOKEN` | pushing `yed2mermaid.rb` to `d-led/homebrew-d-led` |
| `CHOCOLATEY_API_KEY` | `choco push` to community.chocolatey.org |

Both jobs skip themselves when their secret is absent, so a tag never fails
because publishing is not configured. Version tags are protected: they cannot be
deleted, moved or rewritten. Chocolatey scans a package as soon as it arrives,
so that job waits for the release it points at.

Every action is pinned by commit; `actions-up` keeps the pins current.

## Packaging

| Script | Result |
|---|---|
| `scripts/package.sh <version>` | `dist/packages` with five archives and `SHA256SUMS` |
| `scripts/generate-homebrew-formula.sh` | the formula, from the four Unix checksums |
| `scripts/generate-chocolatey-package.sh` | substituted nuspec and install script, packed when `choco` is available |

Each has a PowerShell twin.
