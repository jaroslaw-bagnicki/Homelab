#!/usr/bin/env pwsh
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $TenantId,
  [Parameter(Mandatory)][string] $SubscriptionId,
  [string] $ResourceGroupName  = 'homelab-rg',
  [string] $KeyVaultName       = 'homelab-bysxdb-kv',
  [string] $DisplayName        = 'homelab-oc-agent-sp',
  [int]    $SecretLifetimeDays = 365
)

$ErrorActionPreference = 'Stop'
Set-AzContext -Tenant $TenantId -Subscription $SubscriptionId | Out-Null

$rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
$kvScope = "$rgScope/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
$endDate = (Get-Date).ToUniversalTime().AddDays($SecretLifetimeDays)

$existing = @(Get-AzADServicePrincipal -DisplayName $DisplayName -ErrorAction SilentlyContinue)
if ($existing.Count -gt 1) {
  throw "Multiple service principals named '$DisplayName' found ($($existing.Count)). Disambiguate manually before re-running."
}
$sp = $existing[0]
if ($sp) {
  Write-Warning "Service principal '$DisplayName' already exists (AppId $($sp.AppId)). Rotating its credential."
  $cred = New-AzADSpCredential -ObjectId $sp.Id -EndDate $endDate
  $sp   = Get-AzADServicePrincipal -ObjectId $sp.Id
} else {
  $sp   = New-AzADServicePrincipal -DisplayName $DisplayName -Role Contributor -Scope $rgScope
  $cred = $sp.PasswordCredentials[0]
}

foreach ($r in @{ Contributor = $rgScope; 'Key Vault Secrets User' = $kvScope }.GetEnumerator()) {
  if (-not (Get-AzRoleAssignment -ObjectId $sp.Id -Scope $r.Value -RoleDefinitionName $r.Key -ErrorAction SilentlyContinue)) {
    New-AzRoleAssignment -ObjectId $sp.Id -Scope $r.Value -RoleDefinitionName $r.Key | Out-Null
  }
}

$secrets = @{
  'opencode-agent-sp-homelab-tenant-id'     = $TenantId
  'opencode-agent-sp-homelab-client-id'     = $sp.AppId
  'opencode-agent-sp-homelab-client-secret' = $cred.SecretText
}
$verify = $secrets.Keys | ForEach-Object {
  $name  = $_
  $value = $secrets[$name]
    # Tag the secret with the SP credential's expiry so the vault reflects the
    # rotation deadline. Most relevant for the client-secret; harmless on
    # tenant-id / client-id (they don't rotate).
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $name -SecretValue (ConvertTo-SecureString $value -AsPlainText -Force) -Expires $endDate | Out-Null
  [pscustomobject]@{ Name = $name; Value = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $name -AsPlainText) }
}

Write-Host @"

================================================================
 homelab-oc-agent service principal provisioned
 Stored in Key Vault '$KeyVaultName':
   opencode-agent-sp-homelab-tenant-id
   opencode-agent-sp-homelab-client-id
   opencode-agent-sp-homelab-client-secret  (expires $endDate)

 Injected as container env vars on opencode-homelab:
   AZURE_TENANT_ID
   AZURE_CLIENT_ID
   AZURE_CLIENT_SECRET

 The opencode-homelab agent authenticates to Azure via the SDK
 DefaultAzureCredential chain -> EnvironmentCredential.
================================================================

"@ -ForegroundColor Cyan

$verify | ForEach-Object { Write-Host ("{0,-40} = {1}" -f $_.Name, $_.Value) -ForegroundColor Green }
Write-Host "Role : Contributor on $rgScope" -ForegroundColor Yellow
Write-Host "Role : Key Vault Secrets User on $kvScope" -ForegroundColor Yellow
