#!/usr/bin/env bash
# ── Install OpenCode CLI (idempotent) ───────────────────────────────
set -euo pipefail

OPENCODE_BIN="$HOME/.opencode/bin/opencode"
INSTALL_URL="https://opencode.ai/install"

# Skip if the binary is already in place from a previous install.
if [ -x "$OPENCODE_BIN" ]; then
  echo ":: OpenCode already installed — skipping."
  "$OPENCODE_BIN" --version
  exit 0
fi

echo ":: Installing OpenCode CLI..."
# The official installer is a bash script. curl flags:
#   -f  fail silently on HTTP errors (no body output for 4xx/5xx)
#   -s  silent — suppress progress meter
#   -S  show errors even when silent
#   -L  follow redirects
# Pipe straight into bash to execute the downloaded script.
curl -fsSL "$INSTALL_URL" | bash

# Sanity-check the install actually produced the expected binary.
if [ ! -x "$OPENCODE_BIN" ]; then
  echo ":: ERROR: opencode binary not found at $OPENCODE_BIN after install." >&2
  exit 1
fi

echo ":: OpenCode CLI installed ($("$OPENCODE_BIN" --version))."