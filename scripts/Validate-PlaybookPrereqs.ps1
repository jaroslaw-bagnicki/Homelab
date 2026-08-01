#!/usr/bin/env pwsh
# Pre-flight validation for Ansible playbook execution in the dev container.
# Checks Azure CLI auth, Python package compatibility, and SSH connectivity
# to cloudlab before ansible-playbook runs. Run from the repo root.

$ErrorActionPreference = 'Stop'

$AllGood = $true

function Test-Ok($label) { Write-Host "  OK  $label" -ForegroundColor Green }
function Test-Fail($label, $hint) {
  Write-Host "  FAIL $label" -ForegroundColor Red
  if ($hint) { Write-Host "       $hint" -ForegroundColor Yellow }
  $script:AllGood = $false
}

Write-Host "`n=== Azure CLI + MSAL ===" -ForegroundColor Cyan

# 1. az CLI is on PATH
if (Get-Command az -ErrorAction SilentlyContinue) {
  Test-Ok "az CLI found"
} else {
  Test-Fail "az CLI not on PATH" "Install: apt install azure-cli"
}

# 2. az is logged in
$azAccount = az account show -o json 2>$null | ConvertFrom-Json
if ($azAccount -and $azAccount.user.name) {
  Test-Ok "az logged in as $($azAccount.user.name) (tenant $($azAccount.tenantId))"
} else {
  Test-Fail "az not logged in" "Run: az login --use-device-code"
}

# 3. MSAL + azure-cli-core compatibility (NormalizedResponse check)
$msalCheck = python3 -c @'
import importlib, sys
try:
    msal = importlib.import_module('msal')
    core = importlib.import_module('azure.cli.core._profile')
    from azure.cli.core._profile import Profile
    print(f"msal={msal.__version__} core=" + core.__version__ if hasattr(core, '__version__') else "OK")
except Exception as e:
    print(f"FAIL:{e}")
    sys.exit(0)
'@ 2>&1
if ($msalCheck -notmatch '^FAIL:') {
  Test-Ok "msal + azure-cli-core importable"
} else {
  Test-Fail "msal/azure-cli-core broken" "Run: pip install --break-system-packages 'msal>=1.31' 'msal-extensions>=1.2'"
}

# 4. MSAL cache is readable by Azure CLI
$cacheCheck = python3 -c @'
from azure.cli.core import get_default_cli
from azure.cli.core._profile import Profile
try:
    cli = get_default_cli()
    profile = Profile(cli_ctx=cli)
    cred, sub, tenant = profile.get_login_credentials()
    print(f"OK:{sub}:{tenant}")
except Exception as e:
    print(f"FAIL:{e}")
'@ 2>&1
if ($cacheCheck -match '^OK:') {
  Test-Ok "Azure CLI credential retrieval works"
} else {
  Test-Fail "Azure CLI credential retrieval failed - cache mismatch" "Run: az login --use-device-code, then retry"
}

Write-Host "`n=== Ansible Azure collection ===" -ForegroundColor Cyan

# 5. azure.azcollection is installed
$coll = ansible-galaxy collection list azure.azcollection 2>$null
if ($coll -match 'azure\.azcollection\s+(\S+)') {
  Test-Ok "azure.azcollection $($Matches[1]) installed"
} else {
  Test-Fail "azure.azcollection not installed" "Run: ansible-galaxy collection install azure.azcollection"
}

# 6. Key Python dependencies import (spot-check the ones that failed us)
$deps = @(
  'azure.storage.fileshare',
  'azure.mgmt.postgresqlflexibleservers',
  'azure.identity',
  'azure.keyvault',
  'azure.mgmt.resource'
)
foreach ($dep in $deps) {
  $check = python3 -c "import $dep; print('OK')" 2>&1
  if ($check -match '^OK') {
    Test-Ok "$dep"
  } else {
    Test-Fail "$dep missing" "Run: pip install --break-system-packages -r /home/vscode/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt"
  }
}

Write-Host "`n=== SSH to cloudlab ===" -ForegroundColor Cyan

# 7. ssh-agent has a key loaded
$sshKeys = ssh-add -l 2>&1
if ($LASTEXITCODE -eq 0 -and $sshKeys -match 'ED25519|RSA') {
  Test-Ok "SSH key loaded in agent"
} else {
  Test-Fail "No key in ssh-agent" "Run: Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudlab-vps-key-priv -AsPlainText | ssh-add -"
}

# 8. SSH connectivity to cloudlab
$sshTest = ssh cloudlab "hostname" 2>&1
if ($LASTEXITCODE -eq 0) {
  Test-Ok "SSH to cloudlab ($($sshTest.Trim()))"
} else {
  Test-Fail "SSH to cloudlab failed" "Check ~/.ssh/config, host key, and network"
}

# 9. ansible is on PATH
if (Get-Command ansible-playbook -ErrorAction SilentlyContinue) {
  $ansibleVer = (ansible --version | Select-String 'ansible \[core') -replace '.*\[', '' -replace '\]', ''
  Test-Ok "ansible-playbook ($ansibleVer)"
} else {
  Test-Fail "ansible-playbook not on PATH"
}

Write-Host ""

if ($AllGood) {
  Write-Host "All checks passed. Ready to run ansible-playbook." -ForegroundColor Green
  exit 0
} else {
  Write-Host "Some checks failed. Fix the FAIL items above before running the playbook." -ForegroundColor Red
  exit 1
}
