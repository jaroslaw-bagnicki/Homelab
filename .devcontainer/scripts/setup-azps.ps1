#!/usr/bin/env pwsh
# ── Install Az PowerShell module (idempotent) ───────────────────────
# Runs in background — check progress with: tail -f /tmp/install-az.log
# Az pulls in all sub-modules (Accounts, Resources, Compute, etc.) automatically.

if (Get-Module -ListAvailable -Name Az) {
  Write-Host ":: Az already installed — skipping."
  return
}

Write-Host ":: Installing NuGet provider..."
Install-PackageProvider -Name NuGet -Force

Write-Host ":: Installing Az module..."
Install-Module -Name Az -Force -AllowClobber -Scope CurrentUser

Write-Host ":: Az installed."
