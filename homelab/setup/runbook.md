# Homelab Setup — Runbook

> Step-by-step checklist for setting up the Lenovo ThinkCentre M910q Tiny after receiving the hardware.

## Prerequisites

- [ ] M910q Tiny received, inspected (thermal paste, RAM, SATA, PSU, BIOS)
- [ ] Ubuntu Server 24.04 LTS installed (headless, no GUI)
- [ ] Connected to network via Ethernet (mesh node — subnet `192.168.2.0/24`)
- [ ] Laptop on the same network with SSH client available

---

## 1. Static IP Address

Ubuntu Server's installer (Subiquity) can configure this during install. If already done, skip to step 2. If you need to change it post-install:

### 1.1 Find the network interface name

```bash
ip link
```

Look for the interface starting with `en` (e.g. `enp0s31f6`). Ignore `lo`.

### 1.2 Edit Netplan config

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Replace the contents with (adjust values to your network):

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s31f6:              # ← your interface name
      dhcp4: no
      addresses:
        - 192.168.2.200/24  # ← desired static IP
      routes:
        - to: default
          via: 192.168.2.1  # ← your gateway
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

> **YAML warning**: use spaces only, never tabs.

### 1.3 Apply

```bash
sudo netplan try       # test — reverts on timeout if connectivity lost
sudo netplan apply     # make permanent
```

### 1.4 Verify

```bash
ip addr show enp0s31f6
ip route | grep default
```

---

## 2. SSH Server

Ubuntu Server 24.04 LTS installs `openssh-server` by default if you checked **"Install OpenSSH server"** during setup.

### 2.1 Verify it's running

```bash
sudo systemctl status ssh
```

Expected: `active (running)`.

### 2.2 If missing, install it

```bash
sudo apt update && sudo apt install openssh-server -y
sudo systemctl enable --now ssh
```

### 2.3 Allow SSH through firewall

```bash
sudo ufw allow ssh
```

> Do **not** enable UFW yet — do that after SSH key auth is set up (step 5).

---

## 3. Disk Resizing (LVM)

Ubuntu Server's default LVM layout only allocates ~100 GB to the root volume. Reclaim the full disk:

```bash
# Extend the logical volume to use 100% of free pool space
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv

# Resize the ext4 filesystem to fill the extended volume
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
```

Verify:

```bash
df -h /
```

Expected: ~232 GB (the remainder is ext4 metadata + reserved blocks).

---

## 4. mDNS Service (Avahi — broadcast `homelab.local`)

Avahi daemon lets other devices on the network discover the server by `homelab.local` (mDNS protocol).

```bash
sudo apt update && sudo apt install avahi-daemon -y
sudo systemctl enable --now avahi-daemon
sudo systemctl status avahi-daemon
```

> **Note**: mDNS multicast packets may not cross subnet boundaries. If your mesh router is in Router Mode (separate subnet), `homelab.local` may not resolve from devices on the main router's subnet. In that case, use `~/.ssh/config` (step 5.1) instead.

---

## 5. Install Laptop SSH Key (Key-Based Auth)

### 5.1 (Optional) Configure SSH alias on laptop

Edit `~/.ssh/config` on your **laptop**:

```text
Host homelab
    HostName 192.168.2.200
    User admin
    IdentityFile ~/.ssh/id_ed25519
```

Now you can connect with just `ssh homelab`.

### 5.2 Generate an SSH key pair (on laptop — if you don't already have one)

```bash
ssh-keygen -t ed25519 -C "laptop-jarek"
```

Accept the default location (`~/.ssh/id_ed25519`).

### 5.3 Copy the public key to the server

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub admin@192.168.2.200
```

Enter your server password when prompted.

### 5.4 Test key-based login

```bash
ssh admin@192.168.2.200
```

If it logs in **without asking for a password** (or only asks for the key passphrase), it worked.

### 5.5 Disable password authentication (optional, recommended)

Only do this **after** confirming key-based login works.

```bash
sudo nano /etc/ssh/sshd_config
```

Find and set:

```text
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
```

Restart SSH:

```bash
sudo systemctl restart ssh
```

> **Keep your current SSH session open** while testing a new one — if something breaks, you still have a lifeline.

---

## Verification Checklist

- [ ] Static IP is reachable: `ping 192.168.2.200`
- [ ] SSH works with IP: `ssh admin@192.168.2.200`
- [ ] SSH works with hostname (via Avahi or config): `ssh homelab` / `ssh admin@homelab.local`
- [ ] Full disk space available: `df -h /` → ~232 GB
- [ ] SSH key login works (no password prompt)

---

## Next Steps

After this runbook is complete, proceed to:

- **Base OS hardening**: UFW, fail2ban, unattended-upgrades
- **Docker + Portainer CE** (see execution list in README)
- **Hermes Agent install**
