param(
    [string]$Agent
)

$ErrorActionPreference = 'Stop'

if (-not $env:SSH_AUTH_SOCK) {
    throw 'SSH_AUTH_SOCK is not set; start ssh-agent first.'
}

# ── Azure Key Vault ───────────────────────────────────────────────
if (-not (Get-AzContext)) {
    throw 'Azure context is not set; run Connect-AzAccount first.'
}

$vault = 'homelab-bysxdb-kv'
$password = Get-AzKeyVaultSecret -VaultName $vault -Name 'step-ca-ssh-agent-ai-password' -AsPlainText
$root = Get-AzKeyVaultSecret -VaultName $vault -Name 'ca-root-cert' -AsPlainText

# step only accepts a file for --root and the password, so the workspace lives on
# tmpfs where possible: the CA root never reaches the disk.
$tmp = if ($IsLinux) { '/dev/shm' } else { [IO.Path]::GetTempPath() }
$work = "$tmp/homelab-ssh-agent"
New-Item -ItemType Directory -Path $work -Force | Out-Null
if ($IsLinux) { chmod 700 $work }

try {
    $key = "$work/identity"
    $passwordFile = "$work/password"
    $rootFile = "$work/root.crt"

    Set-Content -LiteralPath $passwordFile -Value $password -NoNewline
    Set-Content -LiteralPath $rootFile -Value $root

    # Make ssh, ssh-keygen and step fail loudly instead of being checked one by one.
    $PSNativeCommandUseErrorActionPreference = $true

    # ── Issue the agent certificate ──────────────────────────────────
    ssh-keygen -t ed25519 -f $key -N '' -q

    step ssh certificate `
        --sign `
        --provisioner 'agent-ai@internal' `
        --provisioner-password-file $passwordFile `
        --ca-url 'https://ca.internal:9000' `
        --root $rootFile `
        "agent-$Agent" "$key.pub"

    ssh-add -t 8h $key

    Write-Host 'agent-ai certificate loaded into ssh-agent.'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
