#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory)]
    [string]$InstanceName
)

$vault = "homelab-bysxdb-kv"
$secretName = "opencode-${InstanceName}-server-password"

function New-OpencodePassword {
    [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(16)).TrimEnd('=')
}

Set-AzKeyVaultSecret -VaultName $vault -Name $secretName `
    -SecretValue (ConvertTo-SecureString -AsPlainText (New-OpencodePassword) -Force) |
    Out-Null

Write-Host "Secret '${secretName}' provisioned in '${vault}'."
