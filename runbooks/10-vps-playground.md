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

## 2. Create a Non-Root User with Sudo

Create the admin user that Ansible will use:

```bash
adduser labadmin
usermod -aG sudo labadmin
```

Verify:
```bash
su - labadmin
sudo whoami   # should print "root"
```

---

## 3. Upload Your SSH Public Key

From your **laptop** (PowerShell), copy your Ed25519 public key to the new user:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@173.249.27.13 "mkdir -p ~labadmin/.ssh && cat >> ~labadmin/.ssh/authorized_keys && chown -R labadmin:labadmin ~labadmin/.ssh && chmod 700 ~labadmin/.ssh && chmod 600 ~labadmin/.ssh/authorized_keys"
```

Test key-only login:
```bash
ssh labadmin@173.249.27.13 -o PreferredAuthentications=publickey
```

---

## 4. Harden SSH

Edit `/etc/ssh/sshd_config` and set these **critical** lines:

```ini
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
```

Optionally, add these for extra hardening:

```ini
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

Restart SSH:
```bash
sudo systemctl restart ssh
```

> ⚠️ **Keep your current root SSH session open** while testing the new config in a
> second terminal. If you lock yourself out, use the Contabo VNC Console at
> [my.contabo.com](https://my.contabo.com/) → your VPS → **VNC Console** —
> it works like a physical monitor + keyboard, even if SSH is broken.

---

## 5. Set Hostname

```bash
sudo hostnamectl set-hostname cloudlab

# Optional: add hostname to /etc/hosts so sudo and hostname -f resolve
# quickly without hitting DNS
echo "127.0.1.1 cloudlab" | sudo tee -a /etc/hosts
```

---

## 6. Map VPS IP to Hostname (on your laptop)

Add the following entry to your laptop's `hosts` file so you can SSH by name
instead of IP:

**Terminal (as Administrator):**
```powershell
code "$env:SystemRoot\System32\drivers\etc\hosts"
```

Add this line at the end of the file:
```
173.249.27.13 cloudlab
```

Verify:
```powershell
ssh labadmin@cloudlab -o PreferredAuthentications=publickey
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

See [research 13: Ansible Adoption](../research/13-ansible-adoption.md) for the
playbook structure. The playbooks will target `cloudlab` (the hostname set above).

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
- [Research 15: VPS Selection](../research/15-vps-selection.md)
- [Research 13: Ansible Adoption](../research/13-ansible-adoption.md)
- [Contabo VNC Console](https://my.contabo.com/) — emergency out-of-band access
