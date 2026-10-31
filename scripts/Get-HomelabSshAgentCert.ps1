[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Agent,
    [string]$CaUrl = 'https://ca.internal:9000',
    [string]$RootPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'

$vault = 'homelab-bysxdb-kv'
$keyId = "agent-$Agent"

if (-not $env:SSH_AUTH_SOCK) {
    throw 'SSH_AUTH_SOCK is not set; start ssh-agent first.'
}

$loaded = ssh-add -L 2>$null
if ($loaded -match 'fleetadm@homelab') {
    throw 'The fleetadm break-glass key is loaded, so ssh would offer it before this certificate. Run ssh-add -D and retry.'
}

if (-not (Get-AzContext)) {
    Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh | Out-Null
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) "homelab-$keyId-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $work | Out-Null
if ($IsLinux) { chmod 700 $work }

try {
    $key = Join-Path $work 'identity'
    $passwordFile = Join-Path $work 'password'

    $password = Get-AzKeyVaultSecret -VaultName $vault -Name 'step-ca-ssh-agent-ai-password' -AsPlainText
    Set-Content -LiteralPath $passwordFile -Value $password -NoNewline

    if (-not $RootPath) {
        $RootPath = Join-Path $work 'root.crt'
        $root = Get-AzKeyVaultSecret -VaultName $vault -Name 'ca-root-cert' -AsPlainText
        Set-Content -LiteralPath $RootPath -Value $root
    }

    ssh-keygen -t ed25519 -f $key -N '' -q
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen could not create the identity key.' }

    step ssh certificate `
        --sign `
        --provisioner 'agent-ai@internal' `
        --provisioner-password-file $passwordFile `
        --ca-url $CaUrl `
        --root $RootPath `
        $keyId "$key.pub"
    if ($LASTEXITCODE -ne 0) { throw 'step could not issue the certificate.' }

    ssh-add $key
    if ($LASTEXITCODE -ne 0) { throw 'ssh-add could not load the certificate into the agent.' }

    Write-Host "agent-ai certificate loaded into ssh-agent (key ID $keyId, principal agent-ai)."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
