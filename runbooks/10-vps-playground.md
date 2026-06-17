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

From your **laptop**, copy the public key to the new user:

```bash
ssh-copy-id labadmin@173.249.27.13
```

Test key-only login:
```bash
ssh labadmin@173.249.27.13 -o PreferredAuthentications=publickey
```

---

## 4. Harden SSH

Edit `/etc/ssh/sshd_config` and set:

```ini
Port 22                    # optional: change to a non-standard port
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

Restart SSH:
```bash
sudo systemctl restart sshd
```

> ⚠️ **Keep your current SSH session open** while testing the new config in a
> second terminal. If you lock yourself out, reconnect via the Contabo panel's
> VNC console.

---

## 5. Set Hostname

```bash
sudo hostnamectl set-hostname vps-playground
echo "127.0.1.1 vps-playground" | sudo tee -a /etc/hosts
```

---

## 6. Configure UFW Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh                # or your custom port
sudo ufw --force enable
sudo ufw status verbose
```

---

## 7. Install fail2ban

```bash
sudo apt install fail2ban -y
sudo systemctl enable --now fail2ban
```

Create `/etc/fail2ban/jail.local`:

```ini
[sshd]
enabled   = true
port      = ssh
maxretry  = 3
bantime   = 1h
```

Restart:
```bash
sudo systemctl restart fail2ban
```

---

## 8. Install Docker Engine

```bash
# Remove any old Docker packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt remove -y $pkg 2>/dev/null || true
done

# Add Docker's official GPG key and repo
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker labadmin

# Enable Docker
sudo systemctl enable docker
```

Log out and back in for the group change, then verify:
```bash
docker run hello-world
```

---

## 9. Install Common Tools

```bash
sudo apt install -y git curl wget htop net-tools unzip
```

---

## 10. Configure Timezone & NTP

```bash
sudo timedatectl set-timezone Europe/Warsaw
sudo timedatectl set-ntp true
timedatectl status
```

---

## 11. Verify Hardening

Run a quick sanity check:

```bash
# SSH config
sudo sshd -T | grep -E "(permitrootlogin|passwordauthentication|pubkeyauthentication)"

# Firewall
sudo ufw status verbose

# fail2ban
sudo fail2ban-client status sshd

# Docker
docker info --format '{{.ServerVersion}}'

# Listening ports (should only show SSH + system services)
sudo ss -tlnp
```

---

## Next Steps

- [ ] Write Ansible inventory and `host_vars/` for this VPS
- [ ] Develop Ansible roles matching the setup above (`common`, `security`, `docker_host`)
- [ ] Enrol in Azure Arc (see [runbook 6](6-azure-arc.md))
- [ ] Test destroy-reimage-reconfigure cycle with `cntb` CLI
- [ ] Once playbooks are validated, apply to the physical homelab

---

**References:**
- [ADR 13: Use Contabo Cloud VPS 10 as Ansible Playground](../docs/decisions/260616-13-vps-playground.md)
- [Research 15: VPS Selection](../research/15-vps-selection.md)
- [Research 13: Ansible Adoption](../research/13-ansible-adoption.md)
- [Contabo VNC Console](https://my.contabo.com/) — emergency out-of-band access
