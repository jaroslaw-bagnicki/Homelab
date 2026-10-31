# Break-glass only: loads the root-equivalent fleetadm key into ssh-agent for this
# session. Daily work uses the agent-ai or automation certificate (ADR 41); the
# dev-container profile deliberately loads no fleet key by default.

$ErrorActionPreference = 'Stop'

if (-not $env:SSH_AUTH_SOCK) { throw "SSH_AUTH_SOCK is not set; start ssh-agent (or a fresh shell) first." }
if (-not (Get-AzContext)) { Connect-AzAccount -UseDeviceAuthentication -Tenant cloud5.ovh | Out-Null }

$key = Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name 'fleetadm-key-priv' -AsPlainText -ErrorAction Stop
if (-not $key) { throw "Secret 'fleetadm-key-priv' is empty or missing." }

$null = $key | ssh-add -
if ($LASTEXITCODE -ne 0) { throw "ssh-add failed with exit code $LASTEXITCODE" }

Write-Warning 'fleetadm break-glass key loaded - root-equivalent on every host. Drop it with ssh-add -D or a fresh shell.'
