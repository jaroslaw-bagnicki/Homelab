#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bootstrap the labadmin agent account on a fresh M910q (after the Ubuntu 24.04 install).
.DESCRIPTION
    Connects to the M910q as root via the native ssh client (root authenticates by
    password — the breaking-glass password from Keeper, prompted once by ssh) and
    idempotently:
      - creates the labadmin user (sudo group, locked password) if missing
      - writes /etc/sudoers.d/labadmin with NOPASSWD ALL (for Ansible become)
      - installs the control node's SSH public key for labadmin (key-only agent account)
      - removes the temporary root-SSH permit drop-in and restarts sshd,
        returning root to console-only breaking glass
    No key is installed for root — root is reached by password only.
    Prerequisite: root SSH password login must be enabled for this one bootstrap
    (runbook 25 §2). Removed automatically by this script afterwards.
.PARAMETER TargetHost
    M910q hostname/IP. Default: homelab (resolves on the LAN via LLMNR).
.PARAMETER PubKeyPath
    Control node's public key to install for labadmin. Default: ~/.ssh/id_ed25519.pub
#>
[CmdletBinding()]
param(
  [string] $TargetHost = 'homelab',
  [string] $PubKeyPath = "$HOME/.ssh/id_ed25519.pub"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PubKeyPath)) {
  throw "Public key not found at '$PubKeyPath'."
}
$pubKey = (Get-Content $PubKeyPath -Raw).Trim()

$remote = @'
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

Write-Host "Connecting as root@$TargetHost (native ssh)..." -ForegroundColor Yellow
& ssh -o StrictHostKeyChecking=accept-new "root@$TargetHost" $remote
if ($LASTEXITCODE -ne 0) {
  throw "Remote bootstrap failed (exit $LASTEXITCODE)."
}

Write-Host "labadmin ready. Verify: ssh labadmin@homelab && sudo whoami" -ForegroundColor Green
