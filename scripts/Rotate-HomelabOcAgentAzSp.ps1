#!/usr/bin/env pwsh
# Rotates the client_secret credential on the homelab-oc-agent App Registration
# and updates the opencode-homelab-sp-client-secret secret in homelab-bysxdb-kv.
# The SP object ID is preserved (audit trail stable); only the credential rotates.
# Re-run = one new credential per invocation.
#
# Uses New-AzADAppCredential (portal-visible under Certificates & secrets)
# rather than New-AzADSpCredential (portal-hidden). Both work identically for
# OAuth2 client-credentials flow.

$ErrorActionPreference = 'Stop'

$DisplayName     = 'homelab-oc-agent-sp'
$KeyVaultName    = 'homelab-bysxdb-kv'
$ClientSecretName = 'opencode-homelab-sp-client-secret'

# ── 1. Look up the SP (must exist — fail loudly if not) ───────────────
$sp = @(Get-AzADServicePrincipal -DisplayName $DisplayName -ErrorAction SilentlyContinue)
if ($sp.Count -eq 0) {
  throw "Service principal '$DisplayName' not found. Run scripts/Create-HomelabOcAgentAzSp.ps1 first to provision it, then re-run this script to rotate."
}
if ($sp.Count -gt 1) {
  throw "Multiple service principals named '$DisplayName' found ($($sp.Count)). Disambiguate manually before re-running."
}
$sp = $sp[0]

# ── 2. Generate a new App credential with 90-day expiry (portal-visible) ──
$endDate = (Get-Date).ToUniversalTime().AddDays(90)
$cred    = New-AzADAppCredential -ApplicationId $sp.AppId -EndDate $endDate

# ── 3. Update the AKV client_secret (tenant-id and client-id unchanged)
Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $ClientSecretName `
  -SecretValue (ConvertTo-SecureString $cred.SecretText -AsPlainText -Force) `
  -Expires $endDate | Out-Null

# ── 4. Confirmation (no secret values logged) ────────────────────────
Write-Host ""
Write-Host "Service principal '$DisplayName' rotated." -ForegroundColor Cyan
Write-Host "  AppId         : $($sp.AppId)"
Write-Host "  ObjectId      : $($sp.Id)"
Write-Host "  AKV secret    : $ClientSecretName (in $KeyVaultName)"
Write-Host "  New expiry    : $endDate"
Write-Host ""
Write-Host "Re-run the workload playbook to re-inject the new credential:" -ForegroundColor Yellow
Write-Host "  ansible-playbook ansible/workloads/opencode/opencode-playbook.yml" -ForegroundColor Yellow
