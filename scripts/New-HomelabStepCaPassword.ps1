#!/usr/bin/env pwsh

$vault = "homelab-bysxdb-kv"
$secretName = "step-ca-provisioner-password"

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
    Write-Warning "Secret '${secretName}' already exists - nothing written."
    Write-Host "The JWK provisioner's encryptedKey is bound to this password when 'step ca init' runs, so"
    Write-Host "replacing the secret alone would leave the new password unable to issue while the old one"
    Write-Host "kept working. Rotate the provisioner itself instead - runbook 35 §8."
    exit 0
}

# Alphanumeric generator, matching New-HomelabNutUpsmonPasswords.ps1 — no +/ or = punctuation.
$alphabet = [char[]]((48..57) + (65..90) + (97..122))
[string]$pw = -join (1..32 | ForEach-Object { $alphabet[[Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $alphabet.Length)] })

Set-AzKeyVaultSecret -VaultName $vault -Name $secretName `
    -SecretValue (ConvertTo-SecureString $pw -AsPlainText -Force) `
    -ErrorAction Stop |
    Out-Null

Write-Host "Secret '${secretName}' provisioned in '${vault}'."
Write-Host "The step_ca role fetches it at deploy time and writes the root-only file:// provisioner password."
