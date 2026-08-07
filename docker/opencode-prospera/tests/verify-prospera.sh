#!/usr/bin/env bash
set -euo pipefail

echo "=== opencode-prospera verify ==="

echo "-- base tools --"
verify-base.sh

echo "-- dotnet SDK --"
dotnet --list-sdks

echo "=== OK ==="