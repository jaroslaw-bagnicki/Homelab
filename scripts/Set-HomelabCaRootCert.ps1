[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path
)

$ErrorActionPreference = 'Stop'
$Vault = 'homelab-bysxdb-kv'
$Name = 'ca-root-cert'

$pem = Get-Content -Raw -LiteralPath $Path
if ($pem -notmatch '-----BEGIN CERTIFICATE-----') { throw "$Path is not a PEM certificate" }
if ($pem -match 'PRIVATE KEY') { throw "$Path contains a private key - refusing to publish it" }

$certs = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
$certs.ImportFromPem($pem)
$expires = $certs[0].NotAfter.ToUniversalTime()

Set-AzKeyVaultSecret -VaultName $Vault -Name $Name `
    -SecretValue (ConvertTo-SecureString $pem -AsPlainText -Force) -Expires $expires | Out-Null

if ((Get-AzKeyVaultSecret -VaultName $Vault -Name $Name -AsPlainText).Trim() -ne $pem.Trim()) {
    throw "the secret in $Vault does not read back as the certificate in $Path"
}

Write-Host "Secret '$Name' published in '$Vault' — $($certs[0].Subject), expires $($expires.ToString('yyyy-MM-dd'))"
