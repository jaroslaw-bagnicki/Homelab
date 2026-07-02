#!/usr/bin/env pwsh
# ── Backup OpenCode runtime data to Azure Blob Storage ───────────────
# Bundles /workspaces/.opencode/ into a timestamped tarball and uploads
# to homelabcloud5/opencode-backups/ via Az PowerShell.
#
# Auth reuses the Codespaces SP via env vars (set by Codespaces secret
# forwarding from the Codespaces repo secrets):
#   AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET
# The SP must have Storage Blob Data Contributor on homelabcloud5 —
# granted by scripts/Add-HomelabOpencodeBackupStorage.ps1 (see runbook 15).
#
# Run manually before Dev Container rebuild if you want to preserve
# sessions against /workspaces loss. No automatic scheduling.

[CmdletBinding()]
param(
  [string] $OcRoot             = '/workspaces/.opencode',
  [string] $StorageAccountName = 'homelabcloud5',
  [string] $ResourceGroupName  = 'homelab-rg',
  [string] $ContainerName      = 'opencode-backups'
)

$ErrorActionPreference = 'Stop'

foreach ($envVar in 'AZURE_TENANT_ID','AZURE_CLIENT_ID','AZURE_CLIENT_SECRET') {
  if (-not (Test-Path "Env:$envVar")) {
    throw "Codespaces secret $envVar not set in the environment."
  }
}

if (-not (Test-Path $OcRoot)) {
  Write-Host ":: no OpenCode data at $OcRoot — nothing to back up"
  exit 0
}

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$blobName  = "opencode-${timestamp}.tar.gz"
$localTar  = Join-Path '/tmp' $blobName

Write-Host ":: archiving $OcRoot → $localTar"
# Use /usr/bin/tar to preserve Unix mode bits and ownership (see
# setup-opencode-persist.ps1 for the rationale on tar vs Copy-Item).
$parent = Split-Path -Parent $OcRoot
$leaf   = Split-Path -Leaf $OcRoot
# tar is the comment-stated GNU tar at /usr/bin/tar (also resolves from PATH
# on Ubuntu 24.04 but the explicit path guarantees the right binary).
& /usr/bin/tar -czf $localTar -C $parent $leaf
if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }

Write-Host ":: uploading to https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${blobName}"
$secure = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
$cred   = New-Object PSCredential($env:AZURE_CLIENT_ID, $secure)
Connect-AzAccount -ServicePrincipal -Tenant $env:AZURE_TENANT_ID -Credential $cred | Out-Null

$sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not $sa) {
  Remove-Item -Force $localTar -ErrorAction SilentlyContinue
  throw "Storage account '$StorageAccountName' not found in RG '$ResourceGroupName'. `n" +
        "Deploy per docs/runbooks/7-restic-backup.md (issue #13) first. `n" +
        "Re-run this script after the storage account exists."
}
$ctx = $sa.Context
Set-AzStorageBlobContent -File $localTar -Container $ContainerName -Blob $blobName -Context $ctx -Force | Out-Null

Remove-Item -Force $localTar
Write-Host ":: backup complete: ${blobName}"
Write-Host ":: list:   Get-AzStorageBlob -Container $ContainerName -Context (Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName).Context"
Write-Host ":: restore: see runbook 15"
