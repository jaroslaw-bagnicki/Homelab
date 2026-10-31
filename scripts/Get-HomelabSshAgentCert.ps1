[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Agent,
    [string]$CaUrl = 'https://ca.internal:9000',
    [string]$RootPath
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandArgumentPassing) { $PSNativeCommandArgumentPassing = 'Standard' }
$vault = 'homelab-bysxdb-kv'
$passwordSecret = 'step-ca-ssh-agent-ai-password'
$keyId = "agent-$Agent"

if (-not $env:SSH_AUTH_SOCK) {
    throw "SSH_AUTH_SOCK is not set; start ssh-agent before loading the agent certificate."
}
if (@(& ssh-add -L 2>$null) -match 'fleetadm@homelab') {
    throw "The fleetadm break-glass key is already loaded; ssh would offer it before $keyId. Run 'ssh-add -D' (or start a fresh shell) and retry."
}
if (-not (Get-AzContext)) {
    Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh | Out-Null
}

# Native commands that exit non-zero now throw, replacing the per-command checks.
$PSNativeCommandUseErrorActionPreference = $true
$work = Join-Path ([System.IO.Path]::GetTempPath()) "homelab-$keyId-$([guid]::NewGuid().ToString('N'))"
$passwordFile = Join-Path $work 'password'
$rootFile = Join-Path $work 'root.crt'
$keyFile = Join-Path $work 'identity'
$null = New-Item -ItemType Directory -Path $work
if ($IsLinux) { & chmod 700 $work }

try {
    Set-Content -LiteralPath $passwordFile -NoNewline -Encoding ascii `
        -Value (Get-AzKeyVaultSecret -VaultName $vault -Name $passwordSecret -AsPlainText -ErrorAction Stop)

    if (-not $RootPath) {
        Set-Content -LiteralPath $rootFile -Encoding ascii `
            -Value (Get-AzKeyVaultSecret -VaultName $vault -Name 'ca-root-cert' -AsPlainText -ErrorAction Stop)
        $RootPath = $rootFile
    }

    & ssh-keygen -t ed25519 -f $keyFile -N '' -q
    & step ssh certificate --sign --provisioner 'agent-ai@internal' `
        --provisioner-password-file $passwordFile --ca-url $CaUrl --root $RootPath `
        $keyId "$keyFile.pub"
    & ssh-add $keyFile

    Write-Host "AI-agent certificate loaded (principal agent-ai, key ID $keyId); the shared JWK remains the bearer credential."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
