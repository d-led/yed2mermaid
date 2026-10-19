#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."

echo "+ zig build -Doptimize=ReleaseSmall"
zig build -Doptimize=ReleaseSmall
ls -l zig-out/bin/yed2mermaid
