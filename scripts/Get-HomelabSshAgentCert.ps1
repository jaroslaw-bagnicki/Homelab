param(
    [string]$Agent
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

# Make ssh, ssh-keygen and step fail loudly instead of being checked one by one.
$PSNativeCommandUseErrorActionPreference = $true

$work = Join-Path ([IO.Path]::GetTempPath()) "homelab-$keyId-$(New-Guid)"
New-Item -ItemType Directory -Path $work | Out-Null
if ($IsLinux) { chmod 700 $work }

try {
    $key = Join-Path $work 'identity'
    $passwordFile = Join-Path $work 'password'

    $password = Get-AzKeyVaultSecret -VaultName $vault -Name 'step-ca-ssh-agent-ai-password' -AsPlainText
    Set-Content -LiteralPath $passwordFile -Value $password -NoNewline

    $rootFile = Join-Path $work 'root.crt'
    $root = Get-AzKeyVaultSecret -VaultName $vault -Name 'ca-root-cert' -AsPlainText
    Set-Content -LiteralPath $rootFile -Value $root

    ssh-keygen -t ed25519 -f $key -N '' -q

    step ssh certificate `
        --sign `
        --provisioner 'agent-ai@internal' `
        --provisioner-password-file $passwordFile `
        --ca-url 'https://ca.internal:9000' `
        --root $rootFile `
        $keyId "$key.pub"

    ssh-add $key

    Write-Host "agent-ai certificate loaded into ssh-agent (key ID $keyId, principal agent-ai)."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
