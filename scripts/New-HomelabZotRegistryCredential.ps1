#!/usr/bin/env pwsh
param(
    [string]$UserName = "zot-admin",
    [switch]$Force
)

$vault = "homelab-bysxdb-kv"
$userSecretName = "zot-registry-user"
$passwordSecretName = "zot-registry-password"

function New-ZotRegistryPassword {
    [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd('=')
}

$userExists = Get-AzKeyVaultSecret -VaultName $vault -Name $userSecretName -ErrorAction SilentlyContinue
$passExists = Get-AzKeyVaultSecret -VaultName $vault -Name $passwordSecretName -ErrorAction SilentlyContinue

if ($userExists -or $passExists) {
    if ($Force) {
        Write-Warning "Secrets '${userSecretName}'/'${passwordSecretName}' already exist. Overwriting."
    } else {
        Write-Warning "Secrets '${userSecretName}'/'${passwordSecretName}' already exist. Use -Force to rotate."
        exit 0
    }
}

Set-AzKeyVaultSecret -VaultName $vault -Name $userSecretName `
    -SecretValue (ConvertTo-SecureString -AsPlainText $UserName -Force) |
    Out-Null

Set-AzKeyVaultSecret -VaultName $vault -Name $passwordSecretName `
    -SecretValue (ConvertTo-SecureString -AsPlainText (New-ZotRegistryPassword) -Force) |
    Out-Null

Write-Host "Secrets '${userSecretName}' and '${passwordSecretName}' provisioned in '${vault}'."
Write-Host "The role fetches both at deploy time (zot_registry_user / zot_registry_password)."
Write-Host "Retrieve the password when needed:"
Write-Host "  Get-AzKeyVaultSecret -VaultName ${vault} -Name ${passwordSecretName} -AsPlainText"
