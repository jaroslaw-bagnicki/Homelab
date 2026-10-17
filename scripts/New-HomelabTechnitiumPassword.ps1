#!/usr/bin/env pwsh

$vault = "homelab-bysxdb-kv"
$secretName = "technitium-admin-password"

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
    Write-Host "Rotate the Technitium admin password through its API, then update the secret to match."
    exit 0
}

$alphabet = [char[]]((48..57) + (65..90) + (97..122))
[string]$pw = -join (1..32 | ForEach-Object { $alphabet[[Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $alphabet.Length)] })

Set-AzKeyVaultSecret -VaultName $vault -Name $secretName `
    -SecretValue (ConvertTo-SecureString $pw -AsPlainText -Force) `
    -ErrorAction Stop |
    Out-Null

Write-Host "Secret '${secretName}' provisioned in '${vault}'."
Write-Host "The edge_host role fetches it at deploy time and replaces the factory admin/admin password."
