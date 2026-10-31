#!/usr/bin/env pwsh
# Creates the three SSH JWK provisioner passwords when they are absent.
# The password is bound to the provisioner's encryptedKey at creation time, so
# rotating the Key Vault value alone breaks issuance. To rotate, remove and
# re-add the provisioner (runbook 40), then create a new secret.

$vault = 'homelab-bysxdb-kv'
$secrets = 'step-ca-ssh-hosts-password', 'step-ca-ssh-automation-password', 'step-ca-ssh-agent-ai-password'

foreach ($name in $secrets) {
    $existing = $null
    try {
        $existing = Get-AzKeyVaultSecret -VaultName $vault -Name $name -ErrorAction Stop
    } catch {
        $missing = $_.Exception.Message -match 'SecretNotFound|not found'
        if (-not $missing -and $_.Exception.Response) {
            $missing = $_.Exception.Response.StatusCode.value__ -eq 404
        }
        if (-not $missing) { throw }
    }

    if ($existing) {
        Write-Warning "Secret '${name}' already exists - nothing written."
        Write-Host "  Rotate by removing/re-adding the provisioner, not by overwriting this secret."
        continue
    }

    $alphabet = [char[]]((48..57) + (65..90) + (97..122))
    [string]$pw = -join (1..32 | ForEach-Object { $alphabet[[Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $alphabet.Length)] })
    Set-AzKeyVaultSecret -VaultName $vault -Name $name `
        -SecretValue (ConvertTo-SecureString $pw -AsPlainText -Force) -ErrorAction Stop | Out-Null
    Write-Host "Secret '${name}' provisioned in '${vault}'."
}

Write-Host ''
Write-Host 'Values are not printed. The step_ca role and the SSH certificate scripts read them at use time.'
