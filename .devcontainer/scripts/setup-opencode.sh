#!/usr/bin/env bash
# ── Install OpenCode CLI ─────────────────────────────────────────
# Idempotent — skips if ~/.opencode/bin/opencode already exists.
# Runs the official installer from https://opencode.ai/install.
# Runs AFTER setup-opencode-persist.ps1 so the symlinks to
# /workspaces/.opencode/* are already in place when OpenCode writes
# its initial config / first-run data.

set -euo pipefail

OPENCODE_BIN="$HOME/.opencode/bin/opencode"

if [ -x "$OPENCODE_BIN" ]; then
  echo ":: opencode already installed at $OPENCODE_BIN"
  "$OPENCODE_BIN" --version 2>&1 || true
  exit 0
fi

echo ":: installing opencode via official installer"
curl -fsSL https://opencode.ai/install | bash

if [ ! -x "$OPENCODE_BIN" ]; then
  echo ":: ERROR: opencode binary not found at $OPENCODE_BIN after install" >&2
  exit 1
fi

echo ":: opencode installed: $("$OPENCODE_BIN" --version)"