#!/usr/bin/env pwsh
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$TenantId,
  [Parameter(Mandatory)][string]$SubscriptionId,
  [string]$ResourceGroupName = 'homelab-rg',
  [string]$KeyVaultName      = 'homelab-bysxdb-kv',
  [string]$DisplayName       = 'homelab-codespaces-sp',
  [int]    $SecretLifetimeDays = 365
)

$ErrorActionPreference = 'Stop'
Set-AzContext -Tenant $TenantId -Subscription $SubscriptionId | Out-Null

$rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
$endDate = (Get-Date).ToUniversalTime().AddDays($SecretLifetimeDays)

$existing = Get-AzADServicePrincipal -DisplayName $DisplayName -ErrorAction SilentlyContinue
if ($existing) {
  Write-Warning "Service principal '$DisplayName' already exists (AppId $($existing.AppId)). Rotating its credential."
  $sp   = $existing
  # New-AzADSpCredential generates a new random password; the SecretText is the new credential value
  $cred = New-AzADSpCredential -ObjectId $sp.Id -EndDate $endDate
  # Refresh $sp to pick up the new credential
  $sp   = Get-AzADServicePrincipal -ObjectId $sp.Id
} else {
  # Default signature auto-generates a password credential; the SecretText is on $sp.PasswordCredentials
  $sp   = New-AzADServicePrincipal -DisplayName $DisplayName -Role Contributor -Scope $rgScope
  $cred = $sp.PasswordCredentials[0]
}

$roleAssigned = Get-AzRoleAssignment -ObjectId $sp.Id -Scope $rgScope -RoleDefinitionName 'Contributor' -ErrorAction SilentlyContinue
if (-not $roleAssigned) {
  New-AzRoleAssignment -ObjectId $sp.Id -Scope $rgScope -RoleDefinitionName 'Contributor' | Out-Null
}

$tenantSecret = ConvertTo-SecureString $TenantId        -AsPlainText -Force
$clientSecret = ConvertTo-SecureString $sp.AppId        -AsPlainText -Force
$credSecret   = ConvertTo-SecureString $cred.SecretText -AsPlainText -Force

Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-tenant-id'     -SecretValue $tenantSecret | Out-Null
Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-client-id'     -SecretValue $clientSecret | Out-Null
Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-client-secret' -SecretValue $credSecret   | Out-Null

$verifyTenant = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-tenant-id'     -AsPlainText
$verifyClient = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-client-id'     -AsPlainText
$verifySecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-client-secret' -AsPlainText

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " GH Codespaces for Homelab — Service Principal created"          -ForegroundColor Cyan
Write-Host " Stored in Key Vault '$KeyVaultName':"                          -ForegroundColor Cyan
Write-Host "   codespaces-sp-tenant-id"                                     -ForegroundColor Cyan
Write-Host "   codespaces-sp-client-id"                                     -ForegroundColor Cyan
Write-Host "   codespaces-sp-client-secret  (expires $endDate)"             -ForegroundColor Cyan
Write-Host ""
Write-Host " Paste the three values below into:"                              -ForegroundColor Yellow
Write-Host "   https://github.com/jaroslaw-bagnicki/Homelab"                  -ForegroundColor Yellow
Write-Host "     -> Settings -> Secrets and variables -> Codespaces"          -ForegroundColor Yellow
Write-Host "     -> New repository secret  x 3"                              -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "AZURE_TENANT_ID     = $verifyTenant"     -ForegroundColor Green
Write-Host "AZURE_CLIENT_ID     = $verifyClient"     -ForegroundColor Green
Write-Host "AZURE_CLIENT_SECRET = $verifySecret"     -ForegroundColor Green
Write-Host ""
Write-Host "Role : Contributor on $rgScope"                                   -ForegroundColor Yellow
Write-Host ""
