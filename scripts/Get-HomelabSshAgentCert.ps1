[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Agent,
    [string]$CaUrl = 'https://ca.internal:9000',
    [string]$RootPath
)

$ErrorActionPreference = 'Stop'
$vault = 'homelab-bysxdb-kv'
$passwordSecret = 'step-ca-ssh-agent-ai-password'
$keyId = "agent-$Agent"

if (-not (Get-Command step -ErrorAction SilentlyContinue)) {
    throw "step CLI not found. Install smallstep/cli before issuing the agent certificate."
}
if ($IsLinux -and -not $env:SSH_AUTH_SOCK) {
    throw "SSH_AUTH_SOCK is not set; start ssh-agent before loading the agent certificate."
}
if (-not (Get-AzContext)) {
    Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh | Out-Null
}

$password = Get-AzKeyVaultSecret -VaultName $vault -Name $passwordSecret -AsPlainText -ErrorAction Stop
if (-not $password) { throw "Secret '$passwordSecret' is empty or missing." }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-ssh-agent-$Agent-" + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($work) | Out-Null
if ($IsLinux) { & chmod 700 $work }
$passwordFile = Join-Path $work 'provisioner-password'
$rootFile = Join-Path $work 'root_ca.crt'
$keyFile = Join-Path $work 'identity'

try {
    Set-Content -LiteralPath $passwordFile -Value $password -NoNewline -Encoding ascii
    if ($IsLinux) { & chmod 600 $passwordFile }

    if (-not $RootPath) {
        $root = Get-AzKeyVaultSecret -VaultName $vault -Name 'ca-root-cert' -AsPlainText -ErrorAction Stop
        if (-not $root) { throw "Secret 'ca-root-cert' is empty or missing." }
        Set-Content -LiteralPath $rootFile -Value $root -Encoding ascii
        $RootPath = $rootFile
    }

    & step ssh certificate $keyId $keyFile `
        --provisioner 'agent-ai@internal' `
        --provisioner-password-file $passwordFile `
        --ca-url $CaUrl `
        --root $RootPath `
        --no-password --insecure
    if ($LASTEXITCODE -ne 0) { throw "step ssh certificate failed with exit code $LASTEXITCODE" }

    Write-Host "AI-agent certificate loaded into ssh-agent (principal agent-ai, key ID $keyId)."
    Write-Host "The shared agent-ai JWK remains the bearer credential; the broker will replace it."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
