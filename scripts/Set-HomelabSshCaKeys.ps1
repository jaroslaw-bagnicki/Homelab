[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$HostKeyPath,
    [Parameter(Mandatory)][string]$UserKeyPath
)

$ErrorActionPreference = 'Stop'
$vault = 'homelab-bysxdb-kv'

function Read-SshPublicKey([string]$Path) {
    $key = (Get-Content -Raw -LiteralPath $Path).Trim()
    if ($key -match 'PRIVATE KEY') { throw "$Path contains a private key - refusing to publish it" }
    if ($key -notmatch '^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) ') {
        throw "$Path is not an OpenSSH public key"
    }
    if (($key -split "`n").Count -ne 1) { throw "$Path must contain exactly one public key" }
    return $key
}

$hostKey = Read-SshPublicKey $HostKeyPath
$userKey = Read-SshPublicKey $UserKeyPath

Set-AzKeyVaultSecret -VaultName $vault -Name 'ssh-host-ca-pub' `
    -SecretValue (ConvertTo-SecureString $hostKey -AsPlainText -Force) | Out-Null
Set-AzKeyVaultSecret -VaultName $vault -Name 'ssh-user-ca-pub' `
    -SecretValue (ConvertTo-SecureString $userKey -AsPlainText -Force) | Out-Null

if ((Get-AzKeyVaultSecret -VaultName $vault -Name 'ssh-host-ca-pub' -AsPlainText).Trim() -ne $hostKey) {
    throw "the ssh-host-ca-pub secret does not read back as the supplied key"
}
if ((Get-AzKeyVaultSecret -VaultName $vault -Name 'ssh-user-ca-pub' -AsPlainText).Trim() -ne $userKey) {
    throw "the ssh-user-ca-pub secret does not read back as the supplied key"
}

Write-Host "SSH CA public keys published in '$vault'."
if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
    Write-Host "Host CA fingerprint: $((ssh-keygen -lf $HostKeyPath) -join ' ')"
    Write-Host "User CA fingerprint: $((ssh-keygen -lf $UserKeyPath) -join ' ')"
}
