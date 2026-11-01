#!/usr/bin/env pwsh
param(
    [switch]$Force
)

$vault = "homelab-bysxdb-kv"
$secrets = @(
    "freeipa-directory-manager-password",
    "freeipa-admin-password",
    "freeipa-test-user-password"
)

# Alphanumeric generator, matching the other password scripts — no +/ or = punctuation.
$alphabet = [char[]]((48..57) + (65..90) + (97..122))

foreach ($secretName in $secrets) {
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

    if ($exists -and -not $Force) {
        Write-Warning "Secret '${secretName}' already exists - nothing written. Use -Force to rotate."
        continue
    }

    [string]$pw = -join (1..32 | ForEach-Object { $alphabet[[Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $alphabet.Length)] })

    Set-AzKeyVaultSecret -VaultName $vault -Name $secretName `
        -SecretValue (ConvertTo-SecureString $pw -AsPlainText -Force) `
        -ErrorAction Stop |
        Out-Null

    Write-Host "Secret '${secretName}' provisioned in '${vault}'."
}

Write-Host "The freeipa_server role fetches the Directory Manager and admin passwords at install time."
Write-Host "The test-user password is used interactively for 'ipa passwd m1test' in runbook 41."
