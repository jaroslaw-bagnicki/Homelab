#!/usr/bin/env pwsh
# Creates the homelab-oc-agent service principal and stores its credentials
# in homelab-bysxdb-kv under the opencode-homelab-sp-{tenant-id,client-id,client-secret}
# triplet. One-shot: exits if the SP already exists; does not rotate.

$ErrorActionPreference = 'Stop'

# ── 1. SP existence check ────────────────────────────────────────────
$DisplayName = 'homelab-oc-agent-sp'
$existing    = @(Get-AzADServicePrincipal -DisplayName $DisplayName -ErrorAction SilentlyContinue)
if ($existing.Count -gt 1) {
  throw "Multiple service principals named '$DisplayName' found ($($existing.Count)). Disambiguate manually before re-running."
}
if ($existing.Count -eq 1) {
  Write-Warning "Service principal '$DisplayName' already exists (AppId $($existing[0].AppId)). Exiting — no rotation is performed by this script. To rotate, delete the SP first (Remove-AzADServicePrincipal) and re-run."
  exit 0
}

# ── 2. Derive scope from current Az context ──────────────────────────
$TenantId          = (Get-AzContext).Tenant.Id
$SubscriptionId    = (Get-AzContext).Subscription.Id
$ResourceGroupName = 'homelab-rg'
$KeyVaultName      = 'homelab-bysxdb-kv'
$rgScope           = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
$kvScope           = "$rgScope/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
$endDate           = (Get-Date).ToUniversalTime().AddDays(365)

# ── 3. Create SP (auto-grants Contributor on the RG via -Role/-Scope) ─
Write-Host "Creating service principal '$DisplayName' in tenant $TenantId..."
$sp   = New-AzADServicePrincipal -DisplayName $DisplayName -Role Contributor -Scope $rgScope
$cred = $sp.PasswordCredentials[0]

# ── 4. Grant Key Vault Secrets User on homelab-bysxdb-kv ──────────────
if (-not (Get-AzRoleAssignment -ObjectId $sp.Id -Scope $kvScope -RoleDefinitionName 'Key Vault Secrets User' -ErrorAction SilentlyContinue)) {
  New-AzRoleAssignment -ObjectId $sp.Id -Scope $kvScope -RoleDefinitionName 'Key Vault Secrets User' | Out-Null
}

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

# ── 6. Read back and print ───────────────────────────────────────────
$verify = $secrets.Keys | ForEach-Object {
  [pscustomobject]@{
    Name  = $_
    Value = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_ -AsPlainText)
  }
}

Write-Host @"

================================================================
 homelab-oc-agent service principal created
 Stored in Key Vault '$KeyVaultName':
   opencode-homelab-sp-tenant-id
   opencode-homelab-sp-client-id
   opencode-homelab-sp-client-secret  (expires $endDate)

 Injected as container env vars on opencode-homelab:
   AZURE_TENANT_ID
   AZURE_CLIENT_ID
   AZURE_CLIENT_SECRET
================================================================

"@ -ForegroundColor Cyan

$verify | ForEach-Object { Write-Host ("{0,-36} = {1}" -f $_.Name, $_.Value) -ForegroundColor Green }
Write-Host "Role : Contributor on $rgScope"                    -ForegroundColor Yellow
Write-Host "Role : Key Vault Secrets User on $kvScope"         -ForegroundColor Yellow
