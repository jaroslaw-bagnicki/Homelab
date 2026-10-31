param(
    [string]$Agent
)

$ErrorActionPreference = 'Stop'

if (-not $env:SSH_AUTH_SOCK) {
    throw 'SSH_AUTH_SOCK is not set; start ssh-agent first.'
}

# ── Azure Key Vault ───────────────────────────────────────────────
if (-not (Get-AzContext)) {
    Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh | Out-Null
}

$vault = 'homelab-bysxdb-kv'
$password = Get-AzKeyVaultSecret -VaultName $vault -Name 'step-ca-ssh-agent-ai-password' -AsPlainText
$root = Get-AzKeyVaultSecret -VaultName $vault -Name 'ca-root-cert' -AsPlainText

# Make ssh, ssh-keygen and step fail loudly instead of being checked one by one.
$PSNativeCommandUseErrorActionPreference = $true

$work = Join-Path ([IO.Path]::GetTempPath()) 'homelab-ssh-agent'
New-Item -ItemType Directory -Path $work -Force | Out-Null
if ($IsLinux) { chmod 700 $work }

try {
    $key = Join-Path $work 'identity'
    $passwordFile = Join-Path $work 'password'
    $rootFile = Join-Path $work 'root.crt'

    Set-Content -LiteralPath $passwordFile -Value $password -NoNewline
    Set-Content -LiteralPath $rootFile -Value $root

    ssh-keygen -t ed25519 -f $key -N '' -q

    step ssh certificate `
        --sign `
        --provisioner 'agent-ai@internal' `
        --provisioner-password-file $passwordFile `
        --ca-url 'https://ca.internal:9000' `
        --root $rootFile `
        "agent-$Agent" "$key.pub"

    ssh-add $key

    Write-Host 'agent-ai certificate loaded into ssh-agent (principal agent-ai).'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
