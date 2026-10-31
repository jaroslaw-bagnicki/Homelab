$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'

$vault = 'homelab-bysxdb-kv'

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
    throw "The fleetadm break-glass key is already loaded; ssh would offer it before the automation certificate. Run 'ssh-add -D' (or start a fresh shell) and retry."
}
if (-not (Get-AzContext)) {
    Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh | Out-Null
}

$password = Get-AzKeyVaultSecret -VaultName $vault -Name 'step-ca-ssh-automation-password' -AsPlainText -ErrorAction Stop
if (-not $password) { throw "Secret 'step-ca-ssh-automation-password' is empty or missing." }

$work = Join-Path ([IO.Path]::GetTempPath()) 'homelab-ssh-automation'
[System.IO.Directory]::CreateDirectory($work) | Out-Null
if ($IsLinux) { & chmod 700 $work }
$passwordFile = Join-Path $work 'provisioner-password'
$rootFile = Join-Path $work 'root_ca.crt'
$keyFile = Join-Path $work 'identity'

try {
    Set-Content -LiteralPath $passwordFile -Value $password -NoNewline -Encoding ascii
    if ($IsLinux) { & chmod 600 $passwordFile }

    $root = Get-AzKeyVaultSecret -VaultName $vault -Name 'ca-root-cert' -AsPlainText -ErrorAction Stop
    if (-not $root) { throw "Secret 'ca-root-cert' is empty or missing." }
    Set-Content -LiteralPath $rootFile -Value $root -Encoding ascii

    & ssh-keygen -t ed25519 -f $keyFile -N '' -q
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed with exit code $LASTEXITCODE" }

    & step ssh certificate `
        --sign `
        --provisioner 'automation@internal' `
        --provisioner-password-file $passwordFile `
        --ca-url 'https://ca.internal:9000' `
        --root $rootFile `
        'automation' "$keyFile.pub"
    if ($LASTEXITCODE -ne 0) { throw "step ssh certificate failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "$keyFile-cert.pub")) { throw "step did not write $keyFile-cert.pub" }

    & ssh-add $keyFile
    if ($LASTEXITCODE -ne 0) { throw "ssh-add failed with exit code $LASTEXITCODE" }

    Write-Host 'Automation certificate loaded into ssh-agent (principal automation).'
    Write-Host "Run 'ssh-add -L' to verify; the private key file is removed when this script exits."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
