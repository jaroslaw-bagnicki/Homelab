#!/usr/bin/env pwsh
# Creates the homelab-oc-agent-sp service principal and stores its credentials
# in homelab-bysxdb-kv under the opencode-homelab-sp-{tenant-id,client-id,client-secret}
# triplet. One-shot: exits if the SP already exists; does not rotate.
# For rotation, use scripts/Rotate-HomelabOcAgentAzSp.ps1.

$ErrorActionPreference = 'Stop'

# ── 1. SP existence check ────────────────────────────────────────────
$DisplayName = 'homelab-oc-agent-sp'
$existing    = @(Get-AzADServicePrincipal -DisplayName $DisplayName -ErrorAction SilentlyContinue)
if ($existing.Count -gt 1) {
  throw "Multiple service principals named '$DisplayName' found ($($existing.Count)). Disambiguate manually before re-running."
}
if ($existing.Count -eq 1) {
  Write-Warning "Service principal '$DisplayName' already exists."
  exit 0
}

# ── 2. Derive scope from current Az context ──────────────────────────
$TenantId          = (Get-AzContext).Tenant.Id
$SubscriptionId    = (Get-AzContext).Subscription.Id
$ResourceGroupName = 'homelab-rg'
$KeyVaultName      = 'homelab-bysxdb-kv'
$endDate           = (Get-Date).ToUniversalTime().AddDays(90)

# ── 3. Validate RG and KV existence before any state change ──────────
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
  throw "Resource group '$ResourceGroupName' not found in subscription $SubscriptionId. Create it first (e.g. via bicep/main.bicep) before running this script."
}
$kv = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction SilentlyContinue
if (-not $kv) {
  throw "Key Vault '$KeyVaultName' not found in subscription $SubscriptionId. Create it first (e.g. via bicep/main.bicep) before running this script."
}
$rgScope = $rg.ResourceId
$kvScope = $kv.ResourceId

# ── 4. Create SP (auto-grants Contributor on the RG via -Role/-Scope) ─
Write-Host "Creating service principal '$DisplayName' in tenant $TenantId..."
$sp   = New-AzADServicePrincipal -DisplayName $DisplayName -Role Contributor -Scope $rgScope
$cred = $sp.PasswordCredentials[0]

# ── 5. Write the three AKV secrets (tagged with the credential expiry) ─
$secrets = @{
  'opencode-homelab-sp-tenant-id'     = $TenantId
  'opencode-homelab-sp-client-id'     = $sp.AppId
  'opencode-homelab-sp-client-secret' = $cred.SecretText
}
foreach ($name in $secrets.Keys) {
  Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $name `
    -SecretValue (ConvertTo-SecureString $secrets[$name] -AsPlainText -Force) `
    -Expires $endDate | Out-Null
}

# ── 6. Grant Key Vault Secrets User on homelab-bysxdb-kv (after the write) ─
if (-not (Get-AzRoleAssignment -ObjectId $sp.Id -Scope $kvScope -RoleDefinitionName 'Key Vault Secrets User' -ErrorAction SilentlyContinue)) {
  New-AzRoleAssignment -ObjectId $sp.Id -Scope $kvScope -RoleDefinitionName 'Key Vault Secrets User' | Out-Null
}

# ── 7. Confirmation (no secret values logged) ────────────────────────
Write-Host ""
Write-Host "homelab-oc-agent-sp service principal created." -ForegroundColor Cyan
Write-Host "  AppId      : $($sp.AppId)"
Write-Host "  ObjectId   : $($sp.Id)"
Write-Host "  Expiry     : $endDate"
Write-Host ""
Write-Host "Stored in Key Vault '$KeyVaultName':" -ForegroundColor Green
foreach ($name in $secrets.Keys) {
  Write-Host "  $name (expires $endDate)"
}
Write-Host ""
Write-Host "Injected as container env vars on opencode-homelab:" -ForegroundColor Green
Write-Host "  AZURE_TENANT_ID"
Write-Host "  AZURE_CLIENT_ID"
Write-Host "  AZURE_CLIENT_SECRET"
Write-Host ""
Write-Host "Role : Contributor on $rgScope"             -ForegroundColor Yellow
Write-Host "Role : Key Vault Secrets User on $kvScope"  -ForegroundColor Yellow
Write-Host ""
Write-Host "Re-run the workload playbook to inject the env vars:" -ForegroundColor Yellow
Write-Host "  ansible-playbook ansible/workloads/opencode/opencode-playbook.yml" -ForegroundColor Yellow
