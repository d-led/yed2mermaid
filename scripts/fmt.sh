#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."

echo "+ zig fmt --check build.zig src"
zig fmt --check build.zig src
echo "formatting is clean"
