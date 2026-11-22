#!/usr/bin/env pwsh
# ── Install the Az PowerShell modules (idempotent) ──────────────────
# Runs in background — check progress with: tail -f /tmp/install-az.log
#
# Installs the modules the repo's scripts actually call, not the `Az`
# meta-package. The meta-package has no installable version metadata on this
# gallery feed — `Install-PSResource -Name Az` fails with
# "Response returned status code package: Not Found", and Install-Module cannot
# bootstrap its NuGet provider either. The named modules install cleanly.
#
# Cmdlet coverage (grep 'Get-Az|New-Az|Set-Az|Connect-Az' scripts/*.ps1):
#   Accounts  — Connect-AzAccount, Get-AzContext, Set-AzContext, Get-AzADServicePrincipal
#   KeyVault  — Get-AzKeyVault, Get-AzKeyVaultSecret, Set-AzKeyVaultSecret
#   Resources — Get-AzResourceGroup, Get-AzRoleAssignment, New-AzRoleAssignment,
#               New-AzResourceGroupDeployment, New-AzADServicePrincipal, New-AzADAppCredential
#   Storage   — Get-AzStorageAccount, Get-AzStorageBlob, Get-AzStorageContainer,
#               New-AzStorageContainer, Set-AzStorageBlobContent
#   Compute   — New-AzSshKey

$modules = @('Az.Accounts', 'Az.KeyVault', 'Az.Resources', 'Az.Storage', 'Az.Compute')

foreach ($m in $modules) {
    if (Get-Module -ListAvailable -Name $m) {
        Write-Host ":: $m already installed"
        continue
    }
    Write-Host ":: Installing $m..."
    Install-PSResource -Name $m -Repository PSGallery -Scope CurrentUser -TrustRepository -ErrorAction Stop
    Write-Host ":: $m installed."
}

Write-Host ":: Az modules ready."
