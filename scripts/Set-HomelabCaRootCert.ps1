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
if ($certs.Count -ne 1) { throw "$Path holds $($certs.Count) certificates - the trust anchor is exactly one" }

$cert = $certs[0]
if ($cert.Subject -ne $cert.Issuer) { throw "$Path is not self-signed - '$($cert.Subject)' was issued by '$($cert.Issuer)'" }
$keyUsage = $cert.Extensions['2.5.29.15'] -as [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]
if (-not $keyUsage -or -not ($keyUsage.KeyUsages -band [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign)) {
    throw "$Path may not sign certificates - not a CA root"
}
$expires = $cert.NotAfter.ToUniversalTime()

Set-AzKeyVaultSecret -VaultName $Vault -Name $Name `
    -SecretValue (ConvertTo-SecureString $pem -AsPlainText -Force) -Expires $expires | Out-Null

if ((Get-AzKeyVaultSecret -VaultName $Vault -Name $Name -AsPlainText).Trim() -ne $pem.Trim()) {
    throw "the secret in $Vault does not read back as the certificate in $Path"
}

Write-Host "Secret '$Name' published in '$Vault' — $($cert.Subject), expires $($expires.ToString('yyyy-MM-dd'))"
