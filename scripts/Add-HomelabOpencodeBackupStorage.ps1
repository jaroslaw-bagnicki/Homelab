#!/usr/bin/env pwsh
# ── Add OpenCode backup container + role grant on homelabcloud5 ──────
# Creates the "opencode-backups" container on homelabcloud5 (deployed
# separately via issue #13's restic setup) and grants the Codespaces SP
# "Storage Blob Data Contributor" on the storage account.
#
# Idempotent — safe to re-run.
#
# Prerequisite: homelabcloud5 storage account must already exist.
# Deploy it first per docs/runbooks/7-restic-backup.md (issue #13).

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $TenantId,
  [Parameter(Mandatory)][string] $SubscriptionId,
  [string] $ResourceGroupName       = 'homelab-rg',
  [string] $StorageAccountName      = 'homelabcloud5',
  [string] $ContainerName           = 'opencode-backups',
  [string] $CodespacesSpDisplayName = 'homelab-codespaces-sp',
  [string] $RoleDefinitionName      = 'Storage Blob Data Contributor'
)

$ErrorActionPreference = 'Stop'
Set-AzContext -Tenant $TenantId -Subscription $SubscriptionId | Out-Null

# 1. Ensure the storage account exists — exit with a clear error if not
$sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not $sa) {
  throw "Storage account '$StorageAccountName' not found in RG '$ResourceGroupName'.`n" +
        "Deploy it first per docs/runbooks/7-restic-backup.md (issue #13).`n" +
        "Re-run this script after the storage account exists."
}

# 2. Create the container (idempotent)
$ctx = $sa.Context
if (-not (Get-AzStorageContainer -Name $ContainerName -Context $ctx -ErrorAction SilentlyContinue)) {
  New-AzStorageContainer -Name $ContainerName -Context $ctx -Permission Off | Out-Null
  Write-Host ":: container '$ContainerName' created" -ForegroundColor Green
} else {
  Write-Host ":: container '$ContainerName' already exists" -ForegroundColor Yellow
}

# 3. Grant the Codespaces SP the data-plane role (idempotent).
# Disambiguate multiple SPs that match the display name (matches the guard
# in scripts/Set-HomelabCodespacesSp.ps1).
$existing = @(Get-AzADServicePrincipal -DisplayName $CodespacesSpDisplayName -ErrorAction SilentlyContinue)
if ($existing.Count -gt 1) {
  throw "Multiple service principals named '$CodespacesSpDisplayName' found ($($existing.Count)). Disambiguate manually before re-running."
}
$sp = $existing[0]
if (-not $sp) {
  throw "Service principal '$CodespacesSpDisplayName' not found. Run scripts/Set-HomelabCodespacesSp.ps1 first."
}
$scope = $sa.Id
$existing = Get-AzRoleAssignment -ObjectId $sp.Id -Scope $scope -RoleDefinitionName $RoleDefinitionName -ErrorAction SilentlyContinue
if (-not $existing) {
  New-AzRoleAssignment -ObjectId $sp.Id -Scope $scope -RoleDefinitionName $RoleDefinitionName | Out-Null
  Write-Host ":: granted '$RoleDefinitionName' to '$CodespacesSpDisplayName' on $scope" -ForegroundColor Green
} else {
  Write-Host ":: role already granted" -ForegroundColor Yellow
}

Write-Host "`n:: OpenCode backup storage ready:" -ForegroundColor Cyan
Write-Host "   https://$StorageAccountName.blob.core.windows.net/$ContainerName/" -ForegroundColor Cyan
