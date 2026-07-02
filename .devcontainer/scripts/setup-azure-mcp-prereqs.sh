#!/usr/bin/env bash
set -u
LOG=/tmp/install-azmcp.log
echo ":: Azure MCP prereq check ($(date -Is))" | tee -a "$LOG"

# Log presence only — never write any prefix of a secret to disk.
present() { [ -n "${1:-}" ] && echo "<set>" || echo "<unset>"; }
mask() { local v="${1:-<unset>}"; [ -n "$v" ] && v="${v:0:4}***"; echo "$v"; }

if [ -n "${AZURE_TENANT_ID:-}" ] && [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_CLIENT_SECRET:-}" ]; then
  echo ":: AZURE_TENANT_ID     = $(mask "$AZURE_TENANT_ID")" | tee -a "$LOG"
  echo ":: AZURE_CLIENT_ID     = $(mask "$AZURE_CLIENT_ID")" | tee -a "$LOG"
  echo ":: AZURE_CLIENT_SECRET = $(present "${AZURE_CLIENT_SECRET:-}")" | tee -a "$LOG"
else
  echo ":: WARNING: one or more AZURE_* env vars missing — Azure MCP will fail to authenticate." | tee -a "$LOG"
  echo ":: Add them at: https://github.com/jaroslaw-bagnicki/Homelab/settings/secrets/codespaces" | tee -a "$LOG"
fi

if command -v npx >/dev/null 2>&1; then
  echo ":: npx version: $(npx --version)" | tee -a "$LOG"
else
  echo ":: WARNING: npx not on PATH — Azure MCP will not start." | tee -a "$LOG"
fi
exit 0
