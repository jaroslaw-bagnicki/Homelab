<#
.SYNOPSIS
    Starts ssh-agent, maps env vars to PowerShell, and loads the VPS SSH key from Key Vault.
.DESCRIPTION
    Run this once per session before connecting to cloudlab. Handles the bash-to-PowerShell
    translation that raw ssh-agent output requires.
#>

# Step 0: Ensure authenticated Az session
if (-not (Get-AzContext)) {
    Write-Host "No Azure connection found. Signing in..." -ForegroundColor Yellow
    Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh
}

# Step 1: Start ssh-agent and set env vars in PowerShell
$agentOutput = ssh-agent
$agentOutput | ForEach-Object {
    if ($_ -match 'SSH_AUTH_SOCK=(.*?);') { $env:SSH_AUTH_SOCK = $Matches[1] }
    if ($_ -match 'SSH_AGENT_PID=(.*?);') { $env:SSH_AGENT_PID = $Matches[1] }
}

if (-not $env:SSH_AUTH_SOCK) {
    Write-Error "Failed to start ssh-agent"
    exit 1
}

Write-Host "ssh-agent started (pid $env:SSH_AGENT_PID)" -ForegroundColor Green
Write-Host "SSH_AUTH_SOCK = $env:SSH_AUTH_SOCK" -ForegroundColor Gray

# Step 2: Load the SSH key from Key Vault
Write-Host "Loading key 'cloudlab-vps-key-priv' from 'homelab-bysxdb-kv'..." -ForegroundColor Yellow
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudlab-vps-key-priv -AsPlainText | ssh-add -

if ($LASTEXITCODE -eq 0) {
    Write-Host "Key loaded successfully." -ForegroundColor Green
} else {
    Write-Error "Failed to load key (exit code: $LASTEXITCODE)"
}
