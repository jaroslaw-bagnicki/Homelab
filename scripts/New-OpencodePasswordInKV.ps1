#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory)]
    [string]$InstanceName,
    [switch]$Force
)

$vault = "homelab-bysxdb-kv"
$secretName = "opencode-${InstanceName}-server-password"

function New-OpencodePassword {
    [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(16)).TrimEnd('=')
}

$existing = Get-AzKeyVaultSecret -VaultName $vault -Name $secretName -ErrorAction SilentlyContinue

if ($existing) {
    if ($Force) {
        Write-Warning "Secret '${secretName}' already exists. Overwriting (rotation)."
    } else {
        Write-Warning "Secret '${secretName}' already exists. Use -Force to rotate."
        exit 0
    }
}

Set-AzKeyVaultSecret -VaultName $vault -Name $secretName `
    -SecretValue (ConvertTo-SecureString -AsPlainText (New-OpencodePassword) -Force) |
    Out-Null

Write-Host "Secret '${secretName}' provisioned in '${vault}'."
