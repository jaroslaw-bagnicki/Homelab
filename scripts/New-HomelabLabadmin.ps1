#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bootstrap the labadmin agent account on a fresh M910q (after the Ubuntu 24.04 install).
.DESCRIPTION
    Connects to the M910q as the personal breaking-glass user via the native ssh client
    (that user authenticates by password — prompted once by ssh; the same password is
    used for sudo, prompted once more by this script) and idempotently:
      - creates the labadmin user (sudo group, locked password) if missing
      - writes /etc/sudoers.d/labadmin with NOPASSWD ALL (for Ansible become)
      - installs the control node's SSH public key for labadmin (key-only agent account)
      - restarts sshd
    No key is installed for the personal user — password SSH is disabled at the end,
    so it stays console-only as the breaking-glass account (runbook 25).
    Prerequisite: the personal user exists with sudo on the M910q (installer profile
    screen, runbook 25 §1).
.PARAMETER TargetHost
    M910q hostname/IP. Default: homelab (resolves on the LAN via LLMNR).
.PARAMETER TargetUser
    Personal breaking-glass user on the M910q. Required — pass your install username.
.PARAMETER PubKeyPath
    Control node's public key to install for labadmin. Default: ~/.ssh/id_ed25519.pub
#>
[CmdletBinding()]
param(
  [string] $TargetHost = 'homelab',
  [Parameter(Mandatory = $true)]
  [string] $TargetUser,
  [string] $PubKeyPath = "$HOME/.ssh/id_ed25519.pub"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PubKeyPath)) {
  throw "Public key not found at '$PubKeyPath'."
}
$pubKey = (Get-Content $PubKeyPath -Raw).Trim()

$remote = (@'
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
echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/99-password-off.conf
systemctl restart ssh
'@ -replace "`r`n", "`n").Replace('__PUBKEY__', $pubKey)

# sudo -S reads the first stdin line as the password, then bash -s runs the script.
$secure = Read-Host "Password for $TargetUser@$TargetHost (sudo)" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$pw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host "Connecting as $TargetUser@$TargetHost (native ssh)..." -ForegroundColor Yellow
("$pw`n$remote") | & ssh -o StrictHostKeyChecking=accept-new "$TargetUser@$TargetHost" "sudo -S bash -s"
if ($LASTEXITCODE -ne 0) {
  throw "Remote bootstrap failed (exit $LASTEXITCODE)."
}

Write-Host "labadmin ready. Verify: ssh labadmin@homelab && sudo whoami" -ForegroundColor Green
