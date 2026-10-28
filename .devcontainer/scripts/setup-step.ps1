#!/usr/bin/env pwsh
# ── Install the Smallstep CLI (idempotent) ─────────────────────────
$ErrorActionPreference = 'Stop'

if (Get-Command step -ErrorAction SilentlyContinue) {
    Write-Host ':: step CLI already installed — skipping.'
    exit 0
}

$work = '/var/tmp/step-cli-install'
if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work | Out-Null

Write-Host ':: Resolving the latest Smallstep CLI release...'
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/smallstep/cli/releases/latest' `
    -Headers @{ Accept = 'application/vnd.github+json' }
$asset = $release.assets | Where-Object { $_.name -match '_linux_amd64\.tar\.gz$' } | Select-Object -First 1
$sums = $release.assets | Where-Object { $_.name -eq 'checksums.txt' } | Select-Object -First 1
if (-not $asset -or -not $sums) { throw 'Could not resolve the step CLI release assets.' }

$assetPath = Join-Path $work $asset.name
$sumsPath = Join-Path $work 'checksums.txt'
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $assetPath
Invoke-WebRequest -Uri $sums.browser_download_url -OutFile $sumsPath

$line = Get-Content -LiteralPath $sumsPath |
    Where-Object { $_ -match "\s+$([regex]::Escape($asset.name))$" } |
    Select-Object -First 1
if (-not $line) { throw "No checksum found for $($asset.name)." }
$expected = ($line -split '\s+')[0].ToLowerInvariant()
$actual = (Get-FileHash -Algorithm SHA256 -Path $assetPath).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "Checksum mismatch for $($asset.name)." }

& tar -xzf $assetPath -C $work
if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE." }
$stepBin = Get-ChildItem -Path $work -Recurse -File -Filter step | Select-Object -First 1
if (-not $stepBin) { throw 'The step binary was not found in the release archive.' }

& sudo install -m 0755 $stepBin.FullName /usr/local/bin/step
if ($LASTEXITCODE -ne 0) { throw "Installing step failed with exit code $LASTEXITCODE." }

Remove-Item -LiteralPath $work -Recurse -Force
$version = (& step version) | Select-Object -First 1
Write-Host ":: step CLI installed ($version)."
