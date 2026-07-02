#!/usr/bin/env bash
# ── Install OpenCode CLI (idempotent, inspectable) ──────────────────
set -euo pipefail

OPENCODE_BIN="$HOME/.opencode/bin/opencode"
INSTALL_URL="https://opencode.ai/install"

# Skip if the binary is already in place from a previous install.
if [ -x "$OPENCODE_BIN" ]; then
  echo ":: OpenCode already installed — skipping."
  "$OPENCODE_BIN" --version
  exit 0
fi

echo ":: Downloading official installer to a temp file (for inspection / replay if needed)"
# Download the installer to a temp file first instead of piping `curl | bash`
# directly. This makes the exact script content available on disk for
# inspection, debugging, or replay if something goes wrong mid-install.
# The temp file is removed by the EXIT trap below (success or failure).
installer="$(mktemp --suffix=-opencode-install.sh)"
trap 'rm -f "$installer"' EXIT

# curl flags:
#   -f  fail on HTTP errors (no body output for 4xx/5xx)
#   -s  silent — suppress progress meter
#   -S  show errors even when silent
#   -L  follow redirects
curl -fsSL -o "$installer" "$INSTALL_URL"

echo ":: Running installer"
bash "$installer"

# Sanity-check the install actually produced the expected binary.
if [ ! -x "$OPENCODE_BIN" ]; then
  echo ":: ERROR: opencode binary not found at $OPENCODE_BIN after install." >&2
  echo "::       Installer script preserved at $installer for inspection." >&2
  trap - EXIT
  exit 1
fi

echo ":: OpenCode CLI installed ($("$OPENCODE_BIN" --version))."
