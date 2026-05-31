# Homelab Setup — Runbook

> Step-by-step checklist for setting up the Lenovo ThinkCentre M910q Tiny after receiving the hardware.

## 0. Create a Bootable USB with Ubuntu Server + Clonezilla

> Do this on your laptop **before** touching the server.

- **Goal**: One 64 GB pendrive with both ISOs — Ubuntu Server for installation and Clonezilla/Rescuezilla for future system backups.
- **Tool**: **YUMI** (exFAT/UEFI edition) — multiboot USB creator.

**Steps**:

1. Download **Ubuntu Server 24.04 LTS ISO** and **Rescuezilla ISO** (graphical Clonezilla).
2. Run YUMI, select the pendrive, choose "Try Unlisted ISO" (or Rescuezilla from the list), and add the Rescuezilla ISO.
3. Add the Ubuntu Server ISO to the same pendrive via YUMI.
4. Eject the pendrive — it's ready.

> **Alternative**: If YUMI causes boot issues, use **Rufus** to write a single ISO per pendrive instead.

**Usage**: Boot from the pendrive → YUMI's menu lets you pick which ISO to launch — Rescuezilla for backup/restore or Ubuntu Server for installation.

**Backup process** (when needed later): Boot into Rescuezilla → Backup → select source disk → all partitions → save image to an external 2.5" USB HDD.

## Prerequisites

---

## 1. Install Ubuntu Server — LAN Configuration

> These steps happen **during** the Ubuntu Server 24.04 LTS installation (Subiquity installer).

### 1.1 Boot from USB

1. Insert the bootable USB and power on the server.
2. Press **F12** (or `Fn + F12`) at startup to open the Boot Menu.
3. Select the USB drive and choose **Ubuntu Server** from the YUMI menu.

### 1.2 Configure static IP in the installer

When the installer reaches the **Network connections** screen:

1. The interface (`enp0s31f6`) will show an auto-assigned DHCP IP (e.g. `192.168.2.47`).
2. Select the interface and choose **Edit IPv4**.
3. Change from **Automatic (DHCP)** to **Manual**.
4. Enter the following values:

   | Field | Value |
   |---|---|
   | **Subnet** | `192.168.2.0/24` |
   | **Address** | `192.168.2.200` |
   | **Gateway** | `192.168.2.1` |
   | **Name servers** | `1.1.1.1, 8.8.8.8` |
   | **Search domains** | (leave empty) |

5. Select **Save** and proceed with the rest of the installation.

### 1.3 Verify after installation

Once installed and rebooted, log in and confirm:

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

After enabling UFW later, verify with:

```bash
sudo ufw status verbose
```

Expected output:

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere
22/tcp (v6)                ALLOW IN    Anywhere (v6)
```

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
    HostName homelab.local
    User jarek
    IdentityFile ~/.ssh/id_ed25519
```

Now you can connect with just `ssh homelab`.

### 5.2 Generate an SSH key pair (on laptop — if you don't already have one)

```bash
ssh-keygen -t ed25519 -C "laptop-jarek"
```

Accept the default location (`~/.ssh/id_ed25519`).

### 5.3 Copy the public key to the server

**Option A** — `ssh-copy-id` (Linux/macOS):

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub jarek@homelab.local
```

**Option B** — Manual (Windows 11 — `ssh-copy-id` is not available by default):

1. Display the public key:
   ```powershell
   type $env:USERPROFILE\.ssh\id_ed25519.pub
   ```
   Select and copy the full output (starts with `ssh-ed25519`).

2. SSH into the server with your password:
   ```powershell
   ssh jarek@homelab.local
   ```
|
3. On the server, append the key to authorized keys:
   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILPC7bboMwWtvq47ouyxv2YdqDvRJGsnm+KFwAqscbD5 lenovo-slim" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

4. Log out: `exit`

### 5.4 Test key-based login

```bash
ssh jarek@homelab.local
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

## 6. Base OS Hardening

### 6.1 Enable UFW

```bash
sudo ufw enable
sudo ufw status verbose
```

Expected: `Status: active` and `22/tcp ALLOW IN` listed.

### 6.2 Install & configure Fail2ban

```bash
sudo apt update && sudo apt install fail2ban -y
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

Edit the SSH jail config:

```bash
sudo nano /etc/fail2ban/jail.local
```

Find the `[sshd]` section and set:

```ini
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
maxretry = 3
findtime = 10m
bantime = 1h
```

Restart:

```bash
sudo systemctl restart fail2ban
sudo systemctl status fail2ban
```

### 6.3 Configure unattended-upgrades

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Optionally enable auto-reboot for kernel updates in `/etc/apt/apt.conf.d/50unattended-upgrades`:

```
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

---

## Verification Checklist

- [ ] Static IP is reachable: `ping 192.168.2.200`
- [ ] SSH works with IP: `ssh jarek@192.168.2.200`
- [ ] SSH works with hostname: `ssh jarek@homelab.local` or `ssh homelab`
- [ ] Full disk space available: `df -h /` → ~232 GB
- [ ] mDNS/Avahi is running: `sudo systemctl status avahi-daemon` → `active (running)`
- [ ] SSH key login works (no password prompt)
- [ ] UFW is active and allowing SSH: `sudo ufw status verbose` → `Status: active`, `22/tcp ALLOW IN`
- [ ] Fail2ban is running and monitoring SSH: `sudo fail2ban-client status sshd` → shows jail status
- [ ] Unattended-upgrades is active: `sudo systemctl status unattended-upgrades` → `active (running)`

---

## Next Steps

After this runbook is complete, proceed to:

- **Docker + Portainer CE** (see execution list in README)
- **Hermes Agent install**
