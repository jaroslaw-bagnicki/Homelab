#!/usr/bin/env pwsh
# Generate SSH key via Azure, store private key in Key Vault

$rg   = 'homelab-rg'
$loc  = 'polandcentral'
$kv   = 'homelab-bysxdb-kv'
$keyName = 'cloudlab-vps-key'

$warn = $null
New-AzSshKey -ResourceGroupName $rg -Location $loc -Name $keyName -SshKeyType Ed25519 -WarningVariable warn

foreach ($line in $warn) {
  if ($line -match 'Private key is saved to (.+)') { $privPath = $matches[1] }
  if ($line -match 'Public key is saved to (.+)')  { $pubPath  = $matches[1] }
}

$privKey = Get-Content $privPath -Raw
$pubKey  = Get-Content $pubPath -Raw

$secPriv = ConvertTo-SecureString $privKey.Trim() -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $kv -Name "$keyName-priv" -SecretValue $secPriv

Remove-Item $privPath, $pubPath -Force

Write-Host "Private key stored in $kv/$keyName-priv"
Write-Host "Public key (also in Azure resource $keyName): $($pubKey.Substring(0, 40))..."
