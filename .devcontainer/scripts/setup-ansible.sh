#!/usr/bin/env bash
# ── Install Ansible (idempotent) ────────────────────────────────────
# apt pins ansible-core to an old release for the life of each Ubuntu version, so the
# controller tools come from a pinned pip venv in /opt instead. The ubuntu26.04 base
# ships Python 3.14, and ansible-core 2.22+ requires Python >= 3.13 — bump the pin as
# new ansible-core majors land.
set -euo pipefail

ANSIBLE_VENV=/opt/ansible
ANSIBLE_CORE_PIN='ansible-core==2.22.*'
ANSIBLE_LINT_PIN='ansible-lint==26.*'

if [[ -x /usr/local/bin/ansible && -x /usr/local/bin/ansible-playbook && -x /usr/local/bin/ansible-lint ]] \
   && ansible --version 2>/dev/null | head -n1 | grep -q 'core 2\.22\.' \
   && ansible-lint --version 2>/dev/null | head -n1 | grep -q '^ansible-lint 26\.'; then
  echo ":: Ansible + ansible-lint already installed — skipping."
  exit 0
fi

echo ":: Installing ${ANSIBLE_CORE_PIN} + ${ANSIBLE_LINT_PIN} into ${ANSIBLE_VENV}..."
# The base image normally ships python3-venv, but do not assume it — without it
# `python3 -m venv` fails on a fresh container.
if ! python3 -c 'import venv, ensurepip' &>/dev/null; then
  sudo apt-get update
  sudo apt-get install -y python3-venv
fi
sudo python3 -m venv --clear "$ANSIBLE_VENV"
sudo "$ANSIBLE_VENV/bin/pip" install --quiet --upgrade pip
sudo "$ANSIBLE_VENV/bin/pip" install --quiet "$ANSIBLE_CORE_PIN" "$ANSIBLE_LINT_PIN"
# /usr/local/bin precedes /usr/bin on PATH in every shell (bash and pwsh alike).
sudo ln -sf "$ANSIBLE_VENV"/bin/ansible* /usr/local/bin/
echo ":: $(ansible --version | head -n1) — $(ansible-lint --version 2>/dev/null | head -n1)"

# ── Collections ─────────────────────────────────────────────────────
# $ANSIBLE_VENV is root-owned, so install into the invoking user's collection
# path (~/.ansible/collections) rather than a path under /opt — writing there
# fails with PermissionError. azure.azcollection also needs its Python
# requirements on the controller, or the Key Vault lookups die at runtime with
# "name 'azure_cloud' is not defined".
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"$ANSIBLE_VENV/bin/ansible-galaxy" collection install \
  -r "$REPO_ROOT/ansible/requirements.yml" --force-with-deps

AZ_COLLECTION="$(ls -d "$HOME"/.ansible/collections/ansible_collections/azure/azcollection 2>/dev/null)"
if [[ -n "$AZ_COLLECTION" && -f "$AZ_COLLECTION/requirements-azure.txt" ]]; then
  # Not the full requirements file: it pins azure-cli-core plus ~55 packages,
  # and one of them (uamqp, for Azure Service Bus) is a C extension with no
  # wheel for this Python — "Failed to build wheel for uamqp" aborts the install
  # and leaves azure-* uninstalled, so the Key Vault lookups then die with
  # "name 'azure_cloud' is not defined". Only the Key Vault surface is used here.
  echo ":: Installing Key Vault Python requirements..."
  sudo "$ANSIBLE_VENV/bin/pip" install --quiet \
    "azure-identity==1.7.0" "azure-core==1.28.0" \
    "azure-keyvault==4.2.0" "azure-mgmt-keyvault==10.0.0"
fi
echo ":: Collections ready."
