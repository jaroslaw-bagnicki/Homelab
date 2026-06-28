#!/usr/bin/env pwsh
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $TenantId,
  [Parameter(Mandatory)][string] $SubscriptionId,
  [string] $ResourceGroupName  = 'homelab-rg',
  [string] $KeyVaultName       = 'homelab-bysxdb-kv',
  [string] $DisplayName        = 'homelab-codespaces-sp',
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
  'codespaces-sp-tenant-id'     = $TenantId
  'codespaces-sp-client-id'     = $sp.AppId
  'codespaces-sp-client-secret' = $cred.SecretText
}
$verify = $secrets.Keys | ForEach-Object {
  $name  = $_
  $value = $secrets[$name]
  Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $name -SecretValue (ConvertTo-SecureString $value -AsPlainText -Force) | Out-Null
  [pscustomobject]@{ Name = $name; Value = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $name -AsPlainText) }
}

Write-Host @"

================================================================
 GH Codespaces for Homelab — Service Principal created
 Stored in Key Vault '$KeyVaultName':
   codespaces-sp-tenant-id
   codespaces-sp-client-id
   codespaces-sp-client-secret  (expires $endDate)

 Paste the three values below into:
   https://github.com/jaroslaw-bagnicki/Homelab
     -> Settings -> Secrets and variables -> Codespaces
     -> New repository secret  x 3
================================================================

"@ -ForegroundColor Cyan

$verify | ForEach-Object { Write-Host ("{0,-22} = {1}" -f $_.Name, $_.Value) -ForegroundColor Green }
Write-Host "Role : Contributor on $rgScope" -ForegroundColor Yellow
Write-Host "Role : Key Vault Secrets User on $kvScope" -ForegroundColor Yellow
