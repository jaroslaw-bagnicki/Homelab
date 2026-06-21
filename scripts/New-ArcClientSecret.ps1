<#
.SYNOPSIS
    Creates a client secret for Azure Arc agent connectivity and uploads it to
    Key Vault in one step.
.DESCRIPTION
    Generates a client secret for the homelab-arc-agent App Registration, used
    by azcmagent connect to enroll machines in Azure Arc. The secret text is only
    visible once at creation — this script captures it inline and stores it in
    Key Vault immediately so it's never lost.
#>

# Ensure correct tenant and subscription context
Set-AzContext -Tenant "cloud5.ovh" -SubscriptionName "Cloud5-default" | Out-Null

# App Registration: homelab-arc-agent
# https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/525b1595-071d-469f-a2c6-0680cda35b4b
$appId = "525b1595-071d-469f-a2c6-0680cda35b4b"
$kvName = "homelab-bysxdb-kv"
$secretName = "arc-enrollment-secret"

$endDate = (Get-Date).AddYears(1)

$context = Get-AzContext
Write-Host "Context: tenant $($context.Tenant.Id) / sub $($context.Subscription.Name)" -ForegroundColor Green
Write-Host "  Authenticated as: $($context.Account.Id)" -ForegroundColor Gray
Write-Host "Creating client secret for App Registration 'homelab-arc-agent' ($appId) ..." -ForegroundColor Yellow

# Generate a new client secret with display name
# https://learn.microsoft.com/en-us/dotnet/api/microsoft.azure.powershell.cmdlets.resources.msgraph.models.apiv10.microsoftgraphpasswordcredential
$credential = New-AzADAppCredential `
    -ApplicationId $appId `
    -PasswordCredentials @{
        DisplayName = $secretName
        EndDateTime = $endDate
    }

if (-not $credential.SecretText) {
    Write-Error "Failed to create client secret — secret text is empty."
    exit 1
}

Write-Host "Client secret created successfully." -ForegroundColor Green
Write-Host "  Display name: $($credential.DisplayName)"
Write-Host "  Secret ID:    $($credential.KeyId)"
Write-Host "  Start:        $($credential.StartDateTime)"
Write-Host "  End:          $($credential.EndDateTime)"

# Upload to Key Vault
Write-Host "Uploading to Key Vault $kvName/$secretName ..." -ForegroundColor Yellow
$secureSecret = ConvertTo-SecureString -String $credential.SecretText -AsPlainText -Force
$kvSecret = Set-AzKeyVaultSecret `
    -VaultName $kvName `
    -Name $secretName `
    -SecretValue $secureSecret `
    -Expires $endDate

if ($kvSecret.Id) {
    Write-Host "Secret stored in Key Vault successfully." -ForegroundColor Green
    Write-Host "  KV secret URI: $($kvSecret.Id)"

    # Clean up local variable — secret is safe in KV
    Remove-Variable credential -Force
    Remove-Variable secureSecret -Force
    Remove-Variable kvSecret -Force
    [System.GC]::Collect()
} else {
    Write-Error "Failed to store secret in Key Vault."
    exit 1
}
