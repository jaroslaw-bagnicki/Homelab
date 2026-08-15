#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bootstrap the labadmin agent account on a fresh M910q (after the Ubuntu 24.04 install).
.DESCRIPTION
    Connects to the M910q as root using the breaking-glass password (stored in Keeper)
    and idempotently:
      - creates the labadmin user (locked password, sudo group) if missing
      - writes /etc/sudoers.d/labadmin with NOPASSWD ALL (for Ansible become)
      - uploads the workstation SSH public key to /home/labadmin/.ssh/authorized_keys
      - locks the labadmin password (key-only agent account)
      - removes the temporary root-SSH permit drop-in and restarts sshd,
        returning root to console-only breaking glass
    Prerequisite: root SSH password login must be enabled for this one bootstrap
    (runbook 25 §2). Removed automatically by this script afterwards.
.PARAMETER RootPassword
    Breaking-glass root password (Keeper). Prompted for if not supplied.
.PARAMETER TargetHost
    M910q hostname/IP. Default: homelab (resolves on the LAN via LLMNR).
.PARAMETER PubKeyPath
    Workstation public key to install for labadmin. Default: $env:USERPROFILE\.ssh\id_ed25519.pub
#>
[CmdletBinding()]
param(
  [securestring] $RootPassword,
  [string] $TargetHost = 'homelab',
  [string] $PubKeyPath = "$env:USERPROFILE\.ssh\id_ed25519.pub"
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
  throw "Posh-SSH module is required. Install with: Install-Module Posh-SSH -Scope CurrentUser"
}
Import-Module Posh-SSH

if (-not $RootPassword) {
  $RootPassword = Read-Host -Prompt 'Breaking-glass root password (Keeper)' -AsSecureString
}
if (-not (Test-Path $PubKeyPath)) {
  throw "Public key not found at '$PubKeyPath'."
}
$pubKey = (Get-Content $PubKeyPath -Raw).Trim()

$cred = [pscredential]::new('root', $RootPassword)
$session = New-SSHSession -ComputerName $TargetHost -Credential $cred -AcceptKey

$remoteScript = @'
set -e
id -u labadmin >/dev/null 2>&1 || useradd -m -s /bin/bash labadmin
usermod -aG sudo labadmin
echo 'labadmin ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/labadmin
chmod 440 /etc/sudoers.d/labadmin
mkdir -p /home/labadmin/.ssh && chmod 700 /home/labadmin/.ssh
echo '__PUBKEY__' > /home/labadmin/.ssh/authorized_keys
chmod 600 /home/labadmin/.ssh/authorized_keys
chown -R labadmin:labadmin /home/labadmin/.ssh
passwd -l labadmin
rm -f /etc/ssh/sshd_config.d/99-root-bootstrap.conf
systemctl restart ssh
'@.Replace('__PUBKEY__', $pubKey)

try {
  $result = Invoke-SSHCommand -SSHSession $session -Command $remoteScript
  if ($result.ExitStatus -ne 0) {
    throw "Remote bootstrap failed (exit $($result.ExitStatus)):`n$($result.Error -join "`n")"
  }
  $result.Output | Write-Host
}
finally {
  Remove-SSHSession $session | Out-Null
}

Write-Host "labadmin ready. Verify: ssh labadmin@homelab && sudo whoami" -ForegroundColor Green
