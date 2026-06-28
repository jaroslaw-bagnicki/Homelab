#!/usr/bin/env pwsh
# ── Install OpenCode CLI ─────────────────────────────────────────
# Idempotent — skips if ~/.opencode/bin/opencode already exists.
# Downloads the official installer to a temp file and executes it
# via bash (the installer script itself is bash — uses arrays, $(),
# and other bash-specific constructs).
#
# curl -fsSL https://opencode.ai/install | bash maps to:
#   - Invoke-WebRequest (throws on HTTP errors — equivalent to -f)
#   - redirects followed by default (equivalent to -L)
#   - no progress bar by default (equivalent to -s)
#   - errors surfaced via Write-Error (equivalent to -S)
#
# Runs AFTER setup-opencode-persist.ps1 so the symlinks to
# /workspaces/.opencode/* are already in place when OpenCode writes
# its initial config / first-run data.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$opencodeBin = Join-Path $HOME '.opencode/bin/opencode'

if (Test-Path -LiteralPath $opencodeBin) {
  Write-Host ":: opencode already installed at $opencodeBin"
  & $opencodeBin --version 2>&1 | Write-Host
  exit 0
}

Write-Host ':: installing opencode via official installer'

$installer = [System.IO.Path]::GetTempFileName()
try {
  # -fsSL equivalent: Invoke-WebRequest follows redirects by default,
  # throws on HTTP errors (cleaner than curl -f), no progress bar.
  Invoke-WebRequest -Uri 'https://opencode.ai/install' `
    -OutFile $installer `
    -UseBasicParsing `
    -MaximumRedirection 5
  & bash $installer
  if ($LASTEXITCODE -ne 0) { throw "opencode installer exited with code $LASTEXITCODE" }
}
finally {
  Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $opencodeBin)) {
  throw "opencode binary not found at $opencodeBin after install"
}

$version = (& $opencodeBin --version 2>&1 | Out-String).Trim()
Write-Host ":: opencode installed: $version"