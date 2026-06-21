#!/usr/bin/env bash
# ── Install Ansible (idempotent) ────────────────────────────────────
set -euo pipefail

if command -v ansible-playbook &>/dev/null && command -v ansible-lint &>/dev/null; then
  echo ":: Ansible + ansible-lint already installed — skipping."
  exit 0
fi

echo ":: Installing Ansible + ansible-lint..."
sudo apt-get update
sudo apt-get install -y ansible ansible-lint
echo ":: Ansible + ansible-lint installed."
