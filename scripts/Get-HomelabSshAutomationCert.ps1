[CmdletBinding()]
param(
    [string]$CaUrl = 'https://ca.internal:9000',
    [string]$RootPath,
    [string]$Provisioner = 'automation@internal',
    [string]$KeyId = 'automation'
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandArgumentPassing) { $PSNativeCommandArgumentPassing = 'Standard' }
$vault = 'homelab-bysxdb-kv'
$passwordSecret = 'step-ca-ssh-automation-password'

foreach ($command in 'step', 'ssh-keygen', 'ssh-add') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "$command not found. Install the Smallstep CLI and OpenSSH client."
    }
}
if ($IsLinux -and -not $env:SSH_AUTH_SOCK) {
    throw "SSH_AUTH_SOCK is not set; start ssh-agent before loading the automation certificate."
}
$loaded = @(& ssh-add -L 2>$null)
if ($loaded -match 'fleetadm@homelab') {
    throw "The fleetadm break-glass key is already loaded; ssh would offer it before $KeyId. Run 'ssh-add -D' (or start a fresh shell) and retry."
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

    & ssh-keygen -t ed25519 -f $keyFile -N '' -q
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed with exit code $LASTEXITCODE" }

    & step ssh certificate `
        --sign `
        --provisioner $Provisioner `
        --provisioner-password-file $passwordFile `
        --ca-url $CaUrl `
        --root $RootPath `
        $KeyId "$keyFile.pub"
    if ($LASTEXITCODE -ne 0) { throw "step ssh certificate failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "$keyFile-cert.pub")) { throw "step did not write $keyFile-cert.pub" }

    & ssh-add $keyFile
    if ($LASTEXITCODE -ne 0) { throw "ssh-add failed with exit code $LASTEXITCODE" }

    Write-Host "Automation certificate loaded into ssh-agent (principal automation, key ID $KeyId)."
    Write-Host "Run 'ssh-add -L' to verify; the private key file is removed when this script exits."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
