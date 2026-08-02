#!/usr/bin/env bash
set -euo pipefail

echo "=== opencode-base verify ==="

echo "-- git --"
git --version

echo "-- pwsh --"
pwsh -Version

echo "-- az --"
az --version | head -n 1

echo "-- bicep --"
bicep --version

echo "-- gh --"
gh --version

echo "=== OK ==="