#!/usr/bin/env bash
# ── Install the smallstep CLI (idempotent) ─────────────────────────
set -euo pipefail

if command -v step &>/dev/null; then
  echo ":: step CLI already installed — skipping."
  exit 0
fi

work=/var/tmp/step-cli-install
rm -rf "$work"
mkdir -p "$work"

echo ":: Resolving the latest smallstep CLI release..."
release=$(curl -fsSL https://api.github.com/repos/smallstep/cli/releases/latest)
asset=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(a["name"] for a in d["assets"] if a["name"].endswith("_linux_amd64.tar.gz")))' <<<"$release")
url=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(a["browser_download_url"] for a in d["assets"] if a["name"].endswith("_linux_amd64.tar.gz")))' <<<"$release")
sums=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(a["browser_download_url"] for a in d["assets"] if a["name"]=="checksums.txt"))' <<<"$release")

curl -fsSL -o "$work/$asset" "$url"
curl -fsSL -o "$work/checksums.txt" "$sums"
( cd "$work" && grep " $asset\$" checksums.txt | sha256sum -c - )
tar -xzf "$work/$asset" -C "$work"
step_bin=$(find "$work" -type f -name step | head -n 1)
sudo install -m 0755 "$step_bin" /usr/local/bin/step
rm -rf "$work"
echo ":: step CLI installed ($(step version --short 2>/dev/null || step version | head -n 1))."
