#!/usr/bin/env pwsh
# ── Deploy repo config files to user home directories ──────────────
# Runs synchronously on container create — copies/link config files
# from .devcontainer/config/ to their expected runtime locations.

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$configDir = Join-Path $repoRoot "config"

# ── PowerShell profile ─────────────────────────────────────────────
$profileDir = Split-Path -Parent $PROFILE.CurrentUserAllHosts
if (-not (Test-Path $profileDir)) {
  New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
Copy-Item -Path (Join-Path $configDir "profile.ps1") -Destination $PROFILE.CurrentUserAllHosts -Force
Write-Host ":: PowerShell profile deployed to $($PROFILE.CurrentUserAllHosts)"

# ── SSH config (cloudlab VPS mapping) ──────────────────────────────
$sshDir = "$HOME/.ssh"
if (-not (Test-Path $sshDir)) {
  New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}
$sshConfigPath = Join-Path $sshDir "config"
Copy-Item -Path (Join-Path $configDir "ssh_config") -Destination $sshConfigPath -Force
& chmod 600 $sshConfigPath
Write-Host ":: SSH config deployed to $sshConfigPath"
