# First Boot — Ubuntu Server Setup

> Gemini thread documenting the initial setup of the M910q homelab server after Ubuntu Server 24.04 LTS installation.

## Topic

Step-by-step walkthrough of the homelab's first-boot phase: Windows backup, Ubuntu Server installation, static IP configuration, SSH access, user management, LVM disk resize, and base OS hardening.

---

## Key Findings

### 1. Static IP Configuration

- **Network**: Mesh system creates a separate subnet — the server got `192.168.2.47/24` via DHCP.
- **Router (main)**: `192.168.1.1`
- **Mesh gateway**: `192.168.2.1`
- **Static IP assigned**: `192.168.2.200/24`
- **Configured during Ubuntu Server installer (Subiquity)**:
  - **Subnet**: `192.168.2.0/24`
  - **Address**: `192.168.2.200`
  - **Gateway**: `192.168.2.1`
  - **DNS**: `1.1.1.1, 8.8.8.8`
- **Alternative (post-install via Netplan)**: Edit `/etc/netplan/00-installer-config.yaml`:
  ```yaml
  network:
    version: 2
    renderer: networkd
    ethernets:
      enp0s31f6:
        dhcp4: no
        addresses:
          - 192.168.2.200/24
        routes:
          - to: default
            via: 192.168.2.1
        nameservers:
          addresses: [1.1.1.1, 8.8.8.8]
  ```
  Apply with `sudo netplan try` then `sudo netplan apply`.
- **To verify gateway**: `ip route | grep default` on the server, or `ipconfig` / `netstat -nr` on a client in the same subnet.

### 2. SSH Server

- **Check status**: `sudo systemctl status ssh`
- **Install if missing**: `sudo apt update && sudo apt install openssh-server`
- **Connect from laptop**: `ssh jarek@192.168.2.200`
- **First-connection fingerprint** must be accepted with `yes`.

### 3. LVM Disk Resize (256 GB SSD — only 98 GB mounted)

- **Root cause**: Ubuntu Server's default LVM layout allocates only ~100 GB to the root volume.
- **Fix** (live, no reboot, no data loss):
  ```bash
  # Extend the logical volume to use 100% of free space
  sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
  # Resize the ext4 filesystem to fill the extended LV
  sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
  # Verify
  df -h /
  ```
- **Result**: `232 GB` available (residual ~24 GB is ext4 metadata and reserved blocks).

### 4. Disk Usage Commands

- **Overall**: `df -h`
- **Per-directory**: `sudo du -h --max-depth=1 /`
- **Interactive TUI**: `sudo apt install ncdu && sudo ncdu /`

### 5. Base OS Hardening (Advisory)

- **UFW Firewall**:
  ```bash
  sudo ufw allow ssh
  sudo ufw enable
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
  Verify SSH is listening on port 22:
  ```bash
  sudo ss -tlnp | grep :22
  ```
  > **Docker caveat**: Docker bypasses UFW via direct `iptables` manipulation. Use `-p 127.0.0.1:...` binds + reverse proxy, or `ufw-docker`.

- **Fail2ban**:
  ```bash
  sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
  # Edit /etc/fail2ban/jail.local — [sshd] section:
  #   maxretry = 3, findtime = 10m, bantime = 1h
  sudo systemctl restart fail2ban
  ```

- **Unattended-Upgrades** (automatic security patches):
  ```bash
  sudo apt install unattended-upgrades
  sudo dpkg-reconfigure --priority=low unattended-upgrades
  ```
  Configure auto-reboot in `/etc/apt/apt.conf.d/50unattended-upgrades`:
  ```
  Unattended-Upgrade::Automatic-Reboot "true";
  Unattended-Upgrade::Automatic-Reboot-Time "04:00";
  ```

- **SSH Key-Based Auth** (ED25519):
  ```bash
  # On laptop
  ssh-keygen -t ed25519 -C "laptop-jarek"
  ssh-copy-id -i ~/.ssh/id_ed25519.pub jarek@192.168.2.200
  ```
  After verifying key login works, disable password auth in `/etc/ssh/sshd_config`:
  ```
  PasswordAuthentication no
  ChallengeResponseAuthentication no
  PubkeyAuthentication yes
  ```
  Restart: `sudo systemctl restart ssh`

### 6. Hostname Resolution (mDNS / Avahi)

- **Problem**: `ssh jarek@homelab` timed out — no DNS resolution for the hostname.
- **Solution 1** — `~/.ssh/config` (recommended):
  ```
  Host homelab
      HostName 192.168.2.200
      User jarek
      IdentityFile ~/.ssh/id_ed25519
  ```
  Now `ssh homelab` works directly.

- **Solution 2** — Local `/etc/hosts` entry:
  ```
  192.168.2.200 homelab
  ```
  - Windows: `C:\Windows\System32\drivers\etc\hosts` (as Admin)
  - Linux/macOS: `/etc/hosts` with `sudo`

- **Solution 3** — mDNS (Avahi):
  ```bash
  sudo apt install avahi-daemon
  sudo systemctl status avahi-daemon
  ```
  Then try `ssh jarek@homelab.local`.
  > **Mesh caveat**: mDNS multicast packets may not cross subnet boundaries created by a mesh router in Router Mode.

---

## Decisions Made

| Decision | Choice | Rejected | Reason |
|---|---|---|---|
| Backup tool | Rescuezilla | Raw Clonezilla | GUI is more user-friendly |
| Multiboot method | YUMI (UEFI) | Rufus (single ISO) | Single pendrive for both backup tool + Ubuntu installer |
| Static IP method | Configured in Subiquity installer | Post-install Netplan | Set during installation for immediate network stability |
| IP address | `192.168.2.200/24` | `192.168.1.x` | Server is physically connected to mesh node in `192.168.2.0/24` subnet |
| Disk resize | LVM live resize | Reinstall | No data loss, no reboot |
| Hostname resolution | `~/.ssh/config` | `/etc/hosts`, mDNS/Avahi | Works regardless of mesh networking quirks; also pairs SSH key automatically |

---

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| Rufus (single ISO pendrive) | Rejected | YUMI offers multiboot — backup tool + installer on one drive |
| `192.168.1.x` static IP | Rejected | Server physically connected to mesh node in `192.168.2.0/24` — gateway mismatch |
| mDNS/Avahi for hostname resolution | Rejected (primary) | Multicast may not cross mesh subnet; `~/.ssh/config` is simpler and more reliable |
| `/etc/hosts` on laptop | Acceptable fallback | Works for all tools (ping, browser), but per-machine config |

---

## Open Questions

- Will UFW be enabled with the recommended rules?
- Will fail2ban and unattended-upgrades be configured next?
- Will SSH key-based auth replace password login entirely?
- Is the mesh system configurable to Bridge Mode so mDNS works across subnets?
- Next steps: Docker + Portainer CE (Step 5 in the execution list)?

---

## Source

https://gemini.google.com/share/3bec83a4906e
