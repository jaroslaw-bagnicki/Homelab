#!/usr/bin/env bash
set -euo pipefail

echo "=== opencode-base verify ==="

echo "-- git --"
git --version

echo "-- pwsh --"
pwsh -Version

echo "-- az --"
az --version | head -n 1

echo "-- Az PowerShell module --"
pwsh -NoProfile -Command "Import-Module Az; Write-Host (Get-Module Az).Version"

echo "-- bicep --"
bicep --version

echo "-- gh --"
gh --version

echo "-- opencode --"
opencode --version

echo "=== OK ==="