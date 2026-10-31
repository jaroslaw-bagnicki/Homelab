[CmdletBinding()]
param(
    [string]$KnownHostsPath = (Join-Path $HOME '.ssh/known_hosts'),
    [string]$Pattern = '*.internal,192.168.2.*'
)

$ErrorActionPreference = 'Stop'
$vault = 'homelab-bysxdb-kv'
$key = (Get-AzKeyVaultSecret -VaultName $vault -Name 'ssh-host-ca-pub' -AsPlainText -ErrorAction Stop).Trim()
if (-not $key) { throw 'ssh-host-ca-pub is empty' }

$directory = Split-Path -Parent $KnownHostsPath
if (-not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }

$line = "@cert-authority $Pattern $key"
$existing = if (Test-Path $KnownHostsPath) { @(Get-Content -LiteralPath $KnownHostsPath) } else { @() }
$filtered = $existing | Where-Object { $_ -notmatch '^@cert-authority\s+.*\*\.internal' }
[System.IO.File]::WriteAllLines($KnownHostsPath, @($filtered) + $line)

if ($IsLinux) { & chmod 600 $KnownHostsPath }
Write-Host "known_hosts updated: @cert-authority $Pattern"
