#!/usr/bin/env pwsh
# ── Install Az PowerShell modules (idempotent) ──────────────────────
# Runs in background — check progress with: tail -f /tmp/install-az.log

$required = @('Az', 'Az.Accounts')
$missing = $required | Where-Object { -not (Get-Module -ListAvailable -Name $_) }

if (-not $missing) {
  Write-Host ":: Az modules already installed — skipping."
  return
}

Write-Host ":: Installing NuGet provider..."
Install-PackageProvider -Name NuGet -Force

Write-Host ":: Installing missing modules: $($missing -join ', ')"
Install-Module -Name $missing -Force -AllowClobber -Scope CurrentUser

Write-Host ":: Az modules installed."
