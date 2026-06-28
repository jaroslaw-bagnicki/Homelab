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
  $cred = New-AzADSpCredential -ObjectId $sp.Id -EndDate $endDate -DisplayName "codespaces-$(Get-Date -Format 'yyyyMMdd')"
} else {
  $sp   = New-AzADServicePrincipal -DisplayName $DisplayName -Role Contributor -Scope $rgScope
  $cred = New-AzADSpCredential -ObjectId $sp.Id -EndDate $endDate -DisplayName "codespaces-$(Get-Date -Format 'yyyyMMdd')"
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

$verifyTenant = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-tenant-id'     -AsPlainText).SecretValue
$verifyClient = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-client-id'     -AsPlainText).SecretValue
$verifySecret = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'codespaces-sp-client-secret' -AsPlainText).SecretValue

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
