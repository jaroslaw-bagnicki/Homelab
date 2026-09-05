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

# ── Azure authentication ──────────────────────────────────────────
# The Codespace injects three env vars from repo-level Codespaces
# secrets (AZURE_TENANT_ID / AZURE_CLIENT_ID / AZURE_CLIENT_SECRET)
# when present. See docs/runbooks/14-gh-codespaces-sp-for-homelab.md
# and docs/decisions/16-agent-identity-pattern.md for
# how the underlying homelab-codespaces-sp is provisioned, stored
# in homelab-bysxdb-kv, and granted Contributor on homelab-rg plus
# Key Vault Secrets User on the vault. When the env vars are present,
# authenticate silently as the SP — no interactive prompt. Otherwise
# fall back to device auth against the cloud5.ovh tenant.
if (-not (Get-AzContext)) {
  if ($env:AZURE_TENANT_ID -and $env:AZURE_CLIENT_ID -and $env:AZURE_CLIENT_SECRET) {
    Write-Host ":: Connecting to Azure as Service Principal homelab-codespaces-sp (tenant $env:AZURE_TENANT_ID)..." -ForegroundColor Cyan
    $secureSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
    $credential   = New-Object System.Management.Automation.PSCredential($env:AZURE_CLIENT_ID, $secureSecret)
    Connect-AzAccount -ServicePrincipal -Tenant $env:AZURE_TENANT_ID -Credential $credential | Out-Null
    if (Get-AzContext) {
      Write-Host ":: Authenticated as Service Principal $env:AZURE_CLIENT_ID" -ForegroundColor Green
    } else {
      Write-Host ":: Service Principal login failed — check AZURE_TENANT_ID / AZURE_CLIENT_ID / AZURE_CLIENT_SECRET Codespaces secrets" -ForegroundColor Red
    }
  } else {
    Write-Host ":: No AZURE_* env vars set; falling back to device authentication (cloud5.ovh)..." -ForegroundColor Yellow
    Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh
  }
} else {
  Write-Host ":: Reusing existing Azure context: $((Get-AzContext).Account.Id)" -ForegroundColor DarkGray
}

# Load fleet + VPS keys from Key Vault (ssh-add is idempotent — run every
# session so fleetadm-key-priv is always present, even when the agent already
# holds other keys)
$keyNames = [ordered]@{
  'fleetadm-key-priv'     = 'fleetadm SSH key (fleetadm@homelab)'
  'cloudlab-vps-key-priv' = 'legacy cloudlab VPS SSH key'
}
if ($env:SSH_AUTH_SOCK -and (Get-AzContext -ErrorAction SilentlyContinue)) {
  foreach ($secret in $keyNames.Keys) {
    Write-Host ":: Loading $($keyNames[$secret]) from Key Vault..." -ForegroundColor Yellow
    $key = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name $secret -AsPlainText -ErrorAction SilentlyContinue 2>$null
    if (-not $key) {
      Write-Warning ":: Could not read $secret from Key Vault — check Azure context / vault access"
      continue
    }
    $null = $key | ssh-add - 2>$null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning ":: ssh-add failed for $($keyNames[$secret])"
    }
  }
}
