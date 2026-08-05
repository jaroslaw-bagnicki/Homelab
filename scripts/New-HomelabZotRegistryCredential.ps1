#!/usr/bin/env pwsh
param(
    [string]$UserName = "zot-admin",
    [switch]$Force
)

$vault = "homelab-bysxdb-kv"
$secretName = "zot-registry-password"

function New-ZotRegistryPassword {
    [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd('=')
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
    -SecretValue (ConvertTo-SecureString -AsPlainText (New-ZotRegistryPassword) -Force) |
    Out-Null

Write-Host "Secret '${secretName}' provisioned in '${vault}'."
Write-Host "Registry user is '${UserName}' (matches the zot_registry_user role default)."
Write-Host "Retrieve the password when needed:"
Write-Host "  Get-AzKeyVaultSecret -VaultName ${vault} -Name ${secretName} -AsPlainText"
