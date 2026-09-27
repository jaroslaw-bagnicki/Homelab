#!/usr/bin/env pwsh
param(
    [switch]$Force
)

$vault = "homelab-bysxdb-kv"
$secretName = "victorialogs-basic-auth-password"

$exists = $null
try {
    $exists = Get-AzKeyVaultSecret -VaultName $vault -Name $secretName -ErrorAction Stop
} catch {
    $missing = $_.Exception.Message -match 'SecretNotFound|not found'
    if (-not $missing -and $_.Exception.Response) {
        $missing = $_.Exception.Response.StatusCode.value__ -eq 404
    }
    if (-not $missing) { throw }
}

if ($exists) {
    if ($Force) {
        Write-Warning "Secret '${secretName}' already exists. Overwriting."
    } else {
        Write-Warning "Secret '${secretName}' already exists. Use -Force to rotate."
        exit 0
    }
}

# Alphanumeric generator, matching New-HomelabNutUpsmonPasswords.ps1 — no +/ or = punctuation.
$alphabet = [char[]]((48..57) + (65..90) + (97..122))
[string]$pw = -join (1..32 | ForEach-Object { $alphabet[[Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $alphabet.Length)] })

Set-AzKeyVaultSecret -VaultName $vault -Name $secretName `
    -SecretValue (ConvertTo-SecureString $pw -AsPlainText -Force) `
    -ErrorAction Stop |
    Out-Null

Write-Host "Secret '${secretName}' provisioned in '${vault}'."
Write-Host "The victorialogs_store role fetches it at deploy time and writes the file:// password."
Write-Host "Rotation: re-run with -Force, then re-run the workload playbook."
