#!/usr/bin/env pwsh
param(
    [switch]$Force
)

$vault = 'homelab-bysxdb-kv'
$secrets = 'nut-upsmon-primary-password', 'nut-upsmon-secondary-password'

foreach ($name in $secrets) {
    $existing = Get-AzKeyVaultSecret -VaultName $vault -Name $name -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        Write-Warning "Secret '${name}' already exists. Use -Force to rotate."
        continue
    }
    [string]$pw = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
    Set-AzKeyVaultSecret -VaultName $vault -Name $name `
        -SecretValue (ConvertTo-SecureString $pw -AsPlainText -Force) | Out-Null
    Write-Host "Secret '${name}' provisioned in '${vault}'."
}

Write-Host ''
Write-Host 'Values are not printed - read each one when you substitute it:'
foreach ($name in $secrets) {
    Write-Host "  Get-AzKeyVaultSecret -VaultName $vault -Name $name -AsPlainText"
}
