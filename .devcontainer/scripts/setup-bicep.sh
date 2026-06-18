#!/usr/bin/env bash
# ── Install Bicep CLI (idempotent) ──────────────────────────────────
set -euo pipefail

if command -v bicep &>/dev/null && bicep --version &>/dev/null; then
  echo ":: Bicep CLI already installed — skipping."
  exit 0
fi

echo ":: Installing Bicep CLI..."
curl -fsSL -o /tmp/bicep https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64
chmod +x /tmp/bicep
sudo mv /tmp/bicep /usr/local/bin/bicep
echo ":: Bicep CLI installed ($(bicep --version))."
