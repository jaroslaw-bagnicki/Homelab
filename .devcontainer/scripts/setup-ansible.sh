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

if [[ -x /usr/local/bin/ansible-playbook && -x /usr/local/bin/ansible-lint ]] \
   && ansible --version 2>/dev/null | head -n1 | grep -q 'core 2\.22\.'; then
  echo ":: Ansible + ansible-lint already installed — skipping."
  exit 0
fi

echo ":: Installing ${ANSIBLE_CORE_PIN} + ${ANSIBLE_LINT_PIN} into ${ANSIBLE_VENV}..."
sudo python3 -m venv --clear "$ANSIBLE_VENV"
sudo "$ANSIBLE_VENV/bin/pip" install --quiet --upgrade pip
sudo "$ANSIBLE_VENV/bin/pip" install --quiet "$ANSIBLE_CORE_PIN" "$ANSIBLE_LINT_PIN"
# /usr/local/bin precedes /usr/bin on PATH in every shell (bash and pwsh alike).
sudo ln -sf "$ANSIBLE_VENV"/bin/ansible* /usr/local/bin/
echo ":: $(ansible --version | head -n1) — $(ansible-lint --version 2>/dev/null | head -n1)"
