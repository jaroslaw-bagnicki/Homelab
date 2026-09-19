#!/usr/bin/env pwsh
param(
    [switch]$Force
)

$vault = "homelab-bysxdb-kv"
$secretName = "netdata-stream-api-key"

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

Set-AzKeyVaultSecret -VaultName $vault -Name $secretName `
    -SecretValue (ConvertTo-SecureString -AsPlainText ([guid]::NewGuid().ToString()) -Force) `
    -ErrorAction Stop |
    Out-Null

Write-Host "Secret '${secretName}' provisioned in '${vault}'."
Write-Host "The netdata role fetches it at deploy time (parent + streaming children)."
Write-Host "Rotation: re-run with -Force, then re-run the playbooks."
