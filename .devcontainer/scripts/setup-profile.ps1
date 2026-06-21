#!/usr/bin/env pwsh
# ── Create PowerShell profile with SSH key loader ──────────────────
# Runs synchronously on container create — fast, no external deps.

$profileDir = Split-Path -Parent $PROFILE.CurrentUserAllHosts
if (-not (Test-Path $profileDir)) {
  New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$profileContent = @'
# ── Homelab: auto-start ssh-agent and load VPS key ─────────────────
# Runs once per session — idempotent, non-interactive.

# Start ssh-agent if not already running
if (-not $env:SSH_AUTH_SOCK -or -not (Test-Path $env:SSH_AUTH_SOCK)) {
  $agentOutput = ssh-agent
  $agentOutput | ForEach-Object {
    if ($_ -match 'SSH_AUTH_SOCK=(.*?);') { $env:SSH_AUTH_SOCK = $Matches[1] }
    if ($_ -match 'SSH_AGENT_PID=(.*?);') { $env:SSH_AGENT_PID = $Matches[1] }
  }
}

# Load VPS key from Key Vault if Az is connected and key not already loaded
if ($env:SSH_AUTH_SOCK -and (Get-AzContext -ErrorAction SilentlyContinue)) {
  $loadedKeys = ssh-add -l 2>$null
  if ($LASTEXITCODE -ne 0 -or $loadedKeys -match 'The agent has no identities') {
    Write-Host ":: Loading VPS SSH key from Key Vault..." -ForegroundColor Yellow
    $null = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudlab-vps-key-priv -AsPlainText 2>$null | ssh-add - 2>$null
  }
}
'@

Set-Content -Path $PROFILE.CurrentUserAllHosts -Value $profileContent -Force
Write-Host ":: PowerShell profile created at $($PROFILE.CurrentUserAllHosts)"
