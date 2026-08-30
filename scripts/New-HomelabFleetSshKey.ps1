#!/usr/bin/env pwsh
# Generates the fleet-wide Ansible SSH keypair, stores the private key in Key Vault
# (fleetadm-key-priv), and writes the public key to the committed repo location
# (ansible/roles/common/files/ssh/fleetadm.pub) that the `common` role deploys
# to fleetadm on every host. Re-run with -Force to rotate (regenerate + overwrite KV).

param(
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

$KeyVaultName = 'homelab-bysxdb-kv'
$SecretName   = 'fleetadm-key-priv'
$RepoRoot     = Split-Path $PSScriptRoot -Parent
$PubDest      = Join-Path $RepoRoot 'ansible/roles/common/files/ssh/fleetadm.pub'
$TempPriv     = Join-Path ([System.IO.Path]::GetTempPath()) ('fleetadm-key-' + [guid]::NewGuid().ToString('N'))
$TempPub      = "$TempPriv.pub"

if (-not $Force -and (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -ErrorAction SilentlyContinue)) {
  throw "Secret '$SecretName' already exists in '$KeyVaultName'. Re-run with -Force to rotate."
}

try {
  ssh-keygen -q -t ed25519 -C "fleetadm@homelab" -N '' -f $TempPriv
  if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed (exit code $LASTEXITCODE)" }

  Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName `
    -SecretValue (ConvertTo-SecureString (Get-Content $TempPriv -Raw).Trim() -AsPlainText -Force) | Out-Null

  New-Item -ItemType Directory -Force -Path (Split-Path $PubDest -Parent) | Out-Null
  Copy-Item $TempPub -Destination $PubDest -Force
} finally {
  Remove-Item $TempPriv, $TempPub -Force -ErrorAction SilentlyContinue
}

Write-Host "Private key stored in $KeyVaultName/$SecretName"
Write-Host "Public key written to $PubDest"
Write-Host ""
Write-Host "Load into the agent and verify:" -ForegroundColor Yellow
Write-Host "  Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText | ssh-add -"
Write-Host "  ssh-add -l"
