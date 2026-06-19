# VPS Playground — Initial Setup

> Runbook for setting up the Contabo Cloud VPS 10 as an Ansible playground.
> Unlike the physical homelab (installed from USB), this VPS comes with a
> pre-installed OS — the steps here harden and configure it to match the
> target homelab environment.

**VPS:** `173.249.27.13` — Contabo Cloud VPS 10 (4 vCPU, 8 GB RAM, 75 GB NVMe)
**OS:** Ubuntu 24.04 LTS (pre-installed by Contabo)

---

## 1. First SSH Access

The VPS ships with **root login via password**. Connect immediately:

```bash
ssh root@173.249.27.13
```

Check the current OS and packages:
```bash
cat /etc/os-release
apt update && apt upgrade -y
```

---

## 2. Map VPS IP to Hostname (on your laptop)

Open your hosts file as Administrator:

```powershell
code "$env:SystemRoot\System32\drivers\etc\hosts"
```

Add this line at the end:
```
173.249.27.13 cloudlab
```

All subsequent steps use `cloudlab` instead of the raw IP.

---

## 3. Create labadmin User (on VPS as root)

```bash
adduser labadmin --disabled-password
usermod -aG sudo labadmin
echo "labadmin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/labadmin
chmod 440 /etc/sudoers.d/labadmin
passwd --lock labadmin
```

## 4. Upload SSH Key (from your laptop)

```powershell
ssh root@cloudlab "mkdir -p ~labadmin/.ssh && chown labadmin:labadmin ~labadmin/.ssh && chmod 700 ~labadmin/.ssh"
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@cloudlab "cat >> ~labadmin/.ssh/authorized_keys && chown labadmin:labadmin ~labadmin/.ssh/authorized_keys && chmod 600 ~labadmin/.ssh/authorized_keys"
```

Verify:
```powershell
ssh labadmin@cloudlab
sudo whoami   # should print "root"
```

## 4b. Upload Azure SSH Key

Generate the key pair and store the private key in Key Vault:
```powershell
./runbooks/AzureResources/New-AzureSshKey.ps1
```

Push the public key from the Azure resource to the VPS:
```powershell
$sshKey = Get-AzSshKey -ResourceGroupName homelab-rg -Name cloudlab-vps-key
ssh labadmin@cloudlab "echo '$($sshKey.publicKey)' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

---

## 5. Harden SSH

Open the config in nano:

```bash
sudo nano /etc/ssh/sshd_config
```

Find and change/set these **critical** lines:

```ini
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
```

> ⚠️ Contabo images may have `PasswordAuthentication` set in
> `/etc/ssh/sshd_config.d/50-cloud-init.conf` as well — check that file too
> and ensure it's set to `no` there, or delete the file. The last value wins.

Optionally, add these for extra hardening:

```ini
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

Save (`Ctrl+O`, `Enter`, `Ctrl+X`) and restart SSH:

```bash
sudo systemctl restart ssh
```

> ⚠️ **Keep your current root SSH session open** while testing the new config in a
> second terminal. If you lock yourself out, use the Contabo VNC Console at
> [my.contabo.com](https://my.contabo.com/) → your VPS → **VNC Console** —
> it works like a physical monitor + keyboard, even if SSH is broken.

---

## 6. Set Hostname

```bash
sudo hostnamectl set-hostname cloudlab

# Optional: add hostname to /etc/hosts so sudo and hostname -f resolve
# quickly without hitting DNS
echo "127.0.1.1 cloudlab" | sudo tee -a /etc/hosts
```

---

## 7. Remaining Setup (via Ansible)

The following steps will be automated via Ansible playbooks, not done manually:

- **UFW firewall** — default deny incoming, allow SSH only
- **fail2ban** — 3 retries, 1h ban on SSH
- **Docker Engine** — official repo, `labadmin` in docker group
- **Common tools** — git, curl, htop, etc.
- **NTP** — ensure time sync is enabled (timezone stays UTC on servers)
- **Verification** — SSH config, UFW, fail2ban, Docker, listening ports

See [research 13: Ansible Adoption](../docs/research/13-ansible-adoption.md) for the
playbook structure. The playbooks will target `cloudlab` (the hostname set above).

---

## 8. SSH from DevContainer

Load the private key from Key Vault into ssh-agent (run once per session):

```powershell
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudlab-vps-key-priv -AsPlainText | ssh-add -
```

Create `~/.ssh/config` (one-time setup):

```powershell
@"
Host cloudlab
    HostName 173.249.27.13
    User labadmin
"@ | Set-Content ~/.ssh/config
```

Connect:

```powershell
ssh cloudlab
```

---

## Next Steps

- [ ] Write Ansible inventory and `host_vars/cloudlab.yml` for this VPS
- [ ] Develop Ansible roles: `common` (tools, timezone), `security` (UFW, fail2ban), `docker_host`
- [ ] Run playbooks against `cloudlab` to apply remaining setup
- [ ] Enrol in Azure Arc (see [runbook 6](6-azure-arc.md))
- [ ] Test destroy-reimage-reconfigure cycle with `cntb` CLI
- [ ] Once playbooks are validated, apply to the physical homelab

---

**References:**
- [ADR 13: Use Contabo Cloud VPS 10 as Ansible Playground](../docs/decisions/260616-13-vps-playground.md)
- [Research 15: VPS Selection](../docs/research/15-vps-selection.md)
- [Research 13: Ansible Adoption](../docs/research/13-ansible-adoption.md)
- [Contabo VNC Console](https://my.contabo.com/) — emergency out-of-band access
