param(
    [string] $Agent,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

# The controller principal the azure.azcollection lookups in the roles read from the
# environment — service principal, not the interactive account. All three parts are one
# principal: a partial environment authenticates nothing, so any gap refills all three.
if (-not $env:AZURE_TENANT_ID -or -not $env:AZURE_CLIENT_ID -or -not $env:AZURE_CLIENT_SECRET) {
    $env:AZURE_TENANT_ID = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name codespaces-sp-tenant-id -AsPlainText
    $env:AZURE_CLIENT_ID = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name codespaces-sp-client-id -AsPlainText
    $env:AZURE_CLIENT_SECRET = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name codespaces-sp-client-secret -AsPlainText
}

# Which principal the loaded certificate authenticates as — the certificate blob from the
# agent, never the key material, so nothing is written outside the temp file.
function Get-LoadedPrincipal {
    $cert = ssh-add -L 2>$null | Where-Object { $_ -match '-cert-v01@openssh\.com ' } | Select-Object -First 1
    if (-not $cert) { return }
    $file = [IO.Path]::GetTempFileName()
    Set-Content -LiteralPath $file -Value $cert
    $principal = (ssh-keygen -L -f $file | Select-String 'Principals:' -Context 0, 1).Context.PostContext
    Remove-Item -LiteralPath $file
    "$principal".Trim()
}

# agent-ai is one shared principal — the per-agent distinction is the certificate's key ID.
$want = if ($Agent) { 'agent-ai' } else { 'automation' }
$principal = Get-LoadedPrincipal

if ($Force -or $principal -ne $want) {
    if (-not $env:SSH_AUTH_SOCK -or -not (Test-Path $env:SSH_AUTH_SOCK)) {
        $env:SSH_AUTH_SOCK = (bash -c 'eval $(ssh-agent -s) >/dev/null 2>&1; echo $SSH_AUTH_SOCK').Trim()
    }
    if ($Agent) {
        & "$PSScriptRoot/Get-HomelabSshAgentCert.ps1" -Agent $Agent
    }
    else {
        & "$PSScriptRoot/Get-HomelabSshAutomationCert.ps1"
    }
    $principal = Get-LoadedPrincipal
}

"fleet session: AKV=$([bool]$env:AZURE_CLIENT_SECRET) sock=$env:SSH_AUTH_SOCK cert=$([bool]$principal) principal=$principal"
