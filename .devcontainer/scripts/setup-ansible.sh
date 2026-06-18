#!/usr/bin/env bash
# ── Install Ansible (idempotent) ────────────────────────────────────
set -euo pipefail

if command -v ansible-playbook &>/dev/null; then
  echo ":: Ansible already installed — skipping."
  exit 0
fi

echo ":: Installing Ansible..."
sudo apt-get update
sudo apt-get install -y ansible
echo ":: Ansible installed."
