#!/usr/bin/env pwsh
param(
    [string]$Registry = "zot.cloud5.ovh",
    [string]$PushEndpoint = "127.0.0.1:5000",
    [string]$Namespace = "opencode",
    [string]$Version = "1.0.0",
    [switch]$BuildFirst
)

$ErrorActionPreference = 'Stop'

$Vault = "homelab-bysxdb-kv"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Images = @(
    @{ Local = "opencode-base:multistage-mcr"; Target = "oc-base"; BuildCtx = "docker/opencode-base"; BuildFile = "Dockerfile.multistage-mcr" },
    @{ Local = "opencode-homelab:1.0.0";      Target = "oc-homelab"; BuildCtx = "docker/opencode-homelab"; BuildFile = "Dockerfile" },
    @{ Local = "opencode-prospera:1.0.0";     Target = "oc-prospera"; BuildCtx = "docker/opencode-prospera"; BuildFile = "Dockerfile" }
)

$User = $env:ZOT_USER
$Pass = $env:ZOT_PASSWORD
if (-not $User -or -not $Pass) {
    Write-Host "No ZOT_USER/ZOT_PASSWORD env vars; reading from Key Vault."
    $User = Get-AzKeyVaultSecret -VaultName $Vault -Name "zot-registry-user" -AsPlainText
    $Pass = Get-AzKeyVaultSecret -VaultName $Vault -Name "zot-registry-password" -AsPlainText
}

Write-Host "Logging into $PushEndpoint as $User..."
$Pass | docker login $PushEndpoint -u $User --password-stdin
if ($LASTEXITCODE -ne 0) { throw "docker login failed" }

foreach ($img in $Images) {
    $pushRef = "$PushEndpoint/$Namespace/$($img.Target):$Version"
    if ($BuildFirst) {
        Write-Host "Building $($img.Local) from $($img.BuildCtx)..."
        docker build -f (Join-Path $RepoRoot "$($img.BuildCtx)/$($img.BuildFile)") `
            -t $pushRef (Join-Path $RepoRoot $img.BuildCtx)
        if ($LASTEXITCODE -ne 0) { throw "build failed for $($img.Target)" }
    } else {
        Write-Host "Tagging $($img.Local) -> $pushRef"
        docker tag $img.Local $pushRef
    }
    Write-Host "Pushing $pushRef..."
    docker push $pushRef
    if ($LASTEXITCODE -ne 0) { throw "push failed for $($img.Target)" }
}

Write-Host ""
Write-Host "Verifying pull round-trip via public $Registry..."
foreach ($img in $Images) {
    $publicRef = "$Registry/$Namespace/$($img.Target):$Version"
    docker pull $publicRef
    if ($LASTEXITCODE -ne 0) { throw "pull verify failed for $publicRef" }
    Write-Host "OK  $publicRef"
}

Write-Host ""
Write-Host "All images pushed via $PushEndpoint and pullable at $Registry/$Namespace (version $Version)." -ForegroundColor Green