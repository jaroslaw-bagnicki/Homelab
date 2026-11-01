param(
    [string] $Agent,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

# The controller principal the azure.azcollection lookups in the roles read from the
# environment — service principal, not the interactive account.
if (-not $env:AZURE_CLIENT_ID) {
    $env:AZURE_TENANT_ID = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name codespaces-sp-tenant-id -AsPlainText
    $env:AZURE_CLIENT_ID = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name codespaces-sp-client-id -AsPlainText
    $env:AZURE_CLIENT_SECRET = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name codespaces-sp-client-secret -AsPlainText
}

$hasCert = $false
if ($env:SSH_AUTH_SOCK) { $hasCert = [bool]((ssh-add -l 2>&1) | Select-String 'CERT') }

if ($Force -or -not $hasCert) {
    if (-not $env:SSH_AUTH_SOCK) {
        $env:SSH_AUTH_SOCK = (bash -c 'eval $(ssh-agent -s) >/dev/null 2>&1; echo $SSH_AUTH_SOCK').Trim()
    }
    if ($Agent) {
        & "$PSScriptRoot/Get-HomelabSshAgentCert.ps1" -Agent $Agent
    }
    else {
        & "$PSScriptRoot/Get-HomelabSshAutomationCert.ps1"
    }
}

if ($env:SSH_AUTH_SOCK) { $hasCert = [bool]((ssh-add -l 2>&1) | Select-String 'CERT') }
"fleet session: AKV=$([bool]$env:AZURE_CLIENT_ID) sock=$env:SSH_AUTH_SOCK cert=$hasCert principal=$(if ($Agent) { 'agent-ai' } else { 'automation' })"
