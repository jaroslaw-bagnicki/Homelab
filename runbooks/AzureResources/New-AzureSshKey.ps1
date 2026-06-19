#!/usr/bin/env pwsh
# Generate SSH key via Azure, store private key in Key Vault

$rg   = 'homelab-rg'
$loc  = 'polandcentral'
$kv   = 'homelab-bysxdb-kv'
$keyName = 'cloudlab-vps-key'

New-AzSshKey -ResourceGroupName $rg -Location $loc -Name $keyName -SshKeyType Ed25519

$keyPath = "$HOME/.ssh/$keyName"
$privKey = Get-Content $keyPath -Raw
$pubKey  = Get-Content "$keyPath.pub" -Raw

$secPriv = ConvertTo-SecureString $privKey.Trim() -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $kv -Name "$keyName-priv" -SecretValue $secPriv

Remove-Item $keyPath, "$keyPath.pub" -Force

Write-Host "Private key stored in $kv/$keyName-priv"
Write-Host "Public key (also in Azure resource $keyName): $($pubKey.Substring(0, 40))..."
