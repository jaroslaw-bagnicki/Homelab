#!/usr/bin/env bash
set -euo pipefail

echo "=== opencode-homelab verify ==="

echo "-- base tools --"
verify-base.sh

echo "-- ansible-core --"
PYTHONUNBUFFERED=1 ansible --version 2>&1 | head -n 1

echo "-- ansible-lint --"
ansible-lint --version

echo "=== OK ==="