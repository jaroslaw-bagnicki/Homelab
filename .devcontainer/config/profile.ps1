# ── Homelab: auto-start ssh-agent, ensure Azure context, load VPS key ─
# Runs once per session — idempotent, non-interactive.

# Opencode
$env:PATH = "/home/vscode/.opencode/bin:$env:PATH"

# Start ssh-agent if not already running
if (-not $env:SSH_AUTH_SOCK -or -not (Test-Path $env:SSH_AUTH_SOCK)) {
  $agentOutput = ssh-agent
  $agentOutput | ForEach-Object {
    if ($_ -match 'SSH_AUTH_SOCK=(.*?);') { $env:SSH_AUTH_SOCK = $Matches[1] }
    if ($_ -match 'SSH_AGENT_PID=(.*?);') { $env:SSH_AGENT_PID = $Matches[1] }
  }
}

# Ensure Azure context exists — prompts device auth once per token lifetime
if (-not (Get-AzContext)) {
  Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh
}

# Load VPS key from Key Vault
if ($env:SSH_AUTH_SOCK -and (Get-AzContext -ErrorAction SilentlyContinue)) {
  $loadedKeys = ssh-add -l 2>$null
  if ($LASTEXITCODE -ne 0 -or $loadedKeys -match 'The agent has no identities') {
    Write-Host ":: Loading VPS SSH key from Key Vault..." -ForegroundColor Yellow
    $null = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudlab-vps-key-priv -AsPlainText 2>$null | ssh-add - 2>$null
  }
}
