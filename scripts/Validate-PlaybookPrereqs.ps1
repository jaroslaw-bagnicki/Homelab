#!/usr/bin/env pwsh
# Pre-flight: validate Azure CLI auth, Python package compatibility, and SSH
# connectivity before running ansible-playbook against cloudlab.
# Run from the repo root.

$ErrorActionPreference = 'Stop'

function Ok($t)  { Write-Host "  OK  $t" -ForegroundColor Green }
function Fail($t, $hint) {
  Write-Host "  FAIL $t" -ForegroundColor Red
  if ($hint) { Write-Host "       $hint" -ForegroundColor Yellow }
  $script:Good = $false
}
$Good = $true

Write-Host ""

# 1. az logged in
$azAccount = az account show -o json 2>$null | ConvertFrom-Json
if ($azAccount -and $azAccount.user.name) {
  Ok "az logged in as $($azAccount.user.name)"
} else {
  Fail "az not logged in" "Run: az login --use-device-code"
}

# 2. Credential cache readable (catches MSAL / azure-cli-core mismatch)
$cacheCheck = python3 -c @'
from azure.cli.core import get_default_cli
from azure.cli.core._profile import Profile
cli = get_default_cli()
profile = Profile(cli_ctx=cli)
cred, sub, _ = profile.get_login_credentials()
print(sub)
'@ 2>&1
if ($LASTEXITCODE -eq 0 -and $cacheCheck -match '^[a-f0-9\-]+$') {
  Ok "Azure CLI credentials readable"
} else {
  Fail "Azure CLI credentials unreadable" "Run: pip install --break-system-packages 'msal>=1.31' 'msal-extensions>=1.2', then az login --use-device-code"
}

# 3. azure.azcollection deps importable (Ansible SDK, separate from Azure CLI)
$depCheck = python3 -c 'import azure.identity; print("OK")' 2>&1
if ($depCheck -match '^OK') {
  Ok "azure.azcollection deps OK"
} else {
  Fail "azure.azcollection deps missing" "Run: pip install --break-system-packages -r /home/vscode/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt"
}

# 4. An SSH identity is loaded - the agent starts empty, so a playbook fails closed without one
$identities = @(ssh-add -l 2>&1)
$hasIdentity = $LASTEXITCODE -eq 0
$hasCert = $hasIdentity -and @(ssh-add -L 2>$null | Select-String '-cert-v01@openssh.com').Count -gt 0
if ($hasIdentity) {
  $kind = if ($hasCert) { 'certificate' } else { 'plain key' }
  Ok "$($identities.Count) SSH identity in ssh-agent ($kind)"
} else {
  Fail "No SSH identity in ssh-agent" "LAN nodes: scripts/Get-HomelabSshAutomationCert.ps1 or scripts/Get-HomelabSshAgentCert.ps1 -Agent <name>. cloudlab: scripts/Import-SshKey.ps1 or scripts/Import-HomelabFleetKey.ps1 (no certificate works there)"
}

# 5. SSH to cloudlab
$sshTest = ssh cloudlab "hostname" 2>&1
if ($LASTEXITCODE -eq 0) {
  Ok "SSH to cloudlab ($($sshTest.Trim()))"
} else {
  Fail "SSH to cloudlab failed" "Load the cloudlab identity first: scripts/Import-SshKey.ps1, or the break-glass fleet key"
}

Write-Host ""
if ($Good) {
  Write-Host "Ready to run ansible-playbook." -ForegroundColor Green
  exit 0
} else {
  Write-Host "Fix the FAIL items above, then retry." -ForegroundColor Red
  exit 1
}
