[CmdletBinding()]
param(
    [string]$CaUrl = 'https://ca.internal:9000',
    [string]$RootPath,
    [string]$Provisioner = 'automation@internal',
    [string]$KeyId = 'automation'
)

$ErrorActionPreference = 'Stop'
$vault = 'homelab-bysxdb-kv'
$passwordSecret = 'step-ca-ssh-automation-password'

if (-not (Get-Command step -ErrorAction SilentlyContinue)) {
    throw "step CLI not found. Run .devcontainer/scripts/setup-step.sh or install smallstep/cli."
}
if ($IsLinux -and -not $env:SSH_AUTH_SOCK) {
    throw "SSH_AUTH_SOCK is not set; start ssh-agent before loading the automation certificate."
}
if (-not (Get-AzContext)) {
    Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh | Out-Null
}

$password = Get-AzKeyVaultSecret -VaultName $vault -Name $passwordSecret -AsPlainText -ErrorAction Stop
if (-not $password) { throw "Secret '$passwordSecret' is empty or missing." }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-ssh-automation-" + [guid]::NewGuid().ToString('N'))
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

    & step ssh certificate $KeyId $keyFile `
        --provisioner $Provisioner `
        --provisioner-password-file $passwordFile `
        --ca-url $CaUrl `
        --root $RootPath `
        --no-password --insecure
    if ($LASTEXITCODE -ne 0) { throw "step ssh certificate failed with exit code $LASTEXITCODE" }

    Write-Host "Automation certificate loaded into ssh-agent (principal automation, key ID $KeyId)."
    Write-Host "Run 'ssh-add -L' to verify; the private key file is removed when this script exits."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
