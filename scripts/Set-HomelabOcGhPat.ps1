#!/usr/bin/env pwsh
# Stores a GitHub fine-grained PAT in homelab-bysxdb-kv under
# opencode-homelab-gh-pat for the homelab OpenCode instance.
# One-shot: exits if the secret already exists.
#
# Ansible injects the PAT as the GH_PAT env var on the opencode-homelab
# container; GitHub MCP reads it from opencode.jsonc via {env:GH_PAT}.
#
# Pre-requisites:
#   Az PowerShell module, signed into Azure (Connect-AzAccount)
#   A fine-grained PAT with repo-scoped permissions:
#     Contents: Read/Write, Issues: Read/Write, Pull requests: Read/Write,
#     Metadata: Read, Workflows: Read/Write

param(
    [string]$InstanceName = 'homelab'
)

$ErrorActionPreference = 'Stop'

$KeyVaultName = 'homelab-bysxdb-kv'
$SecretName   = "opencode-$InstanceName-gh-pat"
$TokenUrl     = "https://github.com/settings/personal-access-tokens/new"

# -- 1. Secret existence check (idempotent) ----------------------------
$existing = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -ErrorAction SilentlyContinue
if ($existing) {
  Write-Warning "Secret '$SecretName' already exists in $KeyVaultName."
  exit 0
}

# -- 2. Open GitHub PAT creation page ---------------------------------
Write-Host "Opening GitHub PAT creation page..."
Write-Host "  $TokenUrl"
Write-Host ""
Write-Host "Create a fine-grained PAT with these scopes:"
Write-Host "  - Contents: Read and Write"
Write-Host "  - Issues: Read and Write"
Write-Host "  - Pull requests: Read and Write"
Write-Host "  - Metadata: Read (mandatory)"
Write-Host "  - Workflows: Read and Write"
Write-Host ""
try {
  Start-Process $TokenUrl
} catch {
  Write-Host "(Could not open browser — navigate to the URL above manually)"
}

# -- 3. Prompt for the PAT --------------------------------------------
$pat = Read-Host -Prompt "Paste the fine-grained PAT"

if ([string]::IsNullOrWhiteSpace($pat)) {
  throw "PAT cannot be empty. Aborting."
}

# -- 4. Validate the PAT against the GitHub API -----------------------
Write-Host "Validating PAT..."
$headers = @{
  Authorization = "Bearer $pat"
  Accept        = "application/vnd.github+json"
  'X-GitHub-Api-Version' = '2022-11-28'
}
try {
  $user = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -SkipHttpErrorCheck
  if (-not $user.login) {
    throw "GitHub API returned no user login — the PAT may be invalid or scoped to an org. Verify the token was created correctly."
  }
  Write-Host "PAT validated (authenticated as $($user.login))."
} catch {
  throw "GitHub API validation failed: $($_.Exception.Message). Verify the PAT was created correctly and hasn't expired."
}

# -- 5. Upload to Azure Key Vault -------------------------------------
Write-Host "Uploading PAT to Key Vault '$KeyVaultName'..."
$secretValue = ConvertTo-SecureString -String $pat -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue $secretValue | Out-Null

# -- 6. Confirmation (no secret value logged) -------------------------
Write-Host ""
Write-Host "GH PAT stored in Key Vault '$KeyVaultName'." -ForegroundColor Cyan
Write-Host "  Secret name : $SecretName"
Write-Host "  Instance    : $InstanceName"
Write-Host ""
Write-Host "Re-run the workload playbook to inject the env var:" -ForegroundColor Yellow
Write-Host "  ansible-playbook ansible/workloads/opencode/opencode-playbook.yml" -ForegroundColor Yellow
