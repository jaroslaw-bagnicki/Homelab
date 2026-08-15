# ML110 NAS — Phase 1: OMV 8.x Setup & RAID

> **Implementation runbook for issue [#61 — ML110 NAS Phase 1](https://github.com/jaroslaw-bagnicki/Homelab/issues/61)** (parent [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)).
> Covers BIOS config, OMV 8.x install to the Goodram SSD, mdadm RAID1 arrays, and the
> static IP. Based on [research 23 — ML110 NAS (OMV)](../research/23-ml110-nas-omv.md)
> and the [OMV 8.x install docs](https://docs.openmediavault.org/en/8.x/installation/index.html).
> Runs entirely at the **direct console** — this G5 has **no LO100/iLO** (see §Access).

## Goals

- Configure the BIOS for software RAID: **AHCI**, ICH9R RAID firmware disabled, boot from the Goodram SSD.
- Install **OMV 8.x** on the **Goodram C40 120 GB SSD** (wipe the old Ubuntu LVM).
- Create **mdadm RAID1** arrays: `md0` = 2× 500 GB Hitachis → **XFS**; `md1` = 2× 250 GB → **ext4**.
- Review the **1 TB WD10EZEX** spare content and decide its role.
- Set the **static IP `192.168.2.210`** on `enp14s0` and verify reachability from the M910q.

## Status

- [x] BIOS configured (AHCI, RAID firmware off, SSD boot)
- [x] OMV 8.x installed on the Goodram SSD — **OMV 8.3.1-2**, hostname `omv`, domain `cloud5.ovh`
- [x] NTP + timezone set
- [x] `md0` (2× 500 GB → XFS) online
- [x] `md1` (2× 250 GB → ext4) online
- [x] Arrays survive reboot — **confirmed** (machine rebooted, md0/md1 auto-assembled + mounted)
- [x] Static IP `192.168.2.210` set and verified from the M910q
- [x] 1 TB spare reviewed — **role: offline** (stays disconnected; content not documented — personal data, §7, 2026-08-15)
- [x] OMV web UI reachable at `https://192.168.2.210` (HTTPS-only, §4d)
- [x] SSH hardening — **applied** (key-only, LAN-only, root console-only — §8, 2026-08-15)
- [x] Disk noise tuning — **AAM = quietest on all 4 data drives** (APM/spindown left off — §6, 2026-08-15)
- [ ] OpenCode cloud-instance SSH key (**dropped for now** — instance on Cloudlab, no path to NAS; revisit when it moves home)

> **Execution log — 2026-08-09**
> - BIOS done: `Advanced | Advanced Chipset Control | Serial ATA` → `Serial ATA: Enabled`,
>   `Native Mode Operation: Serial ATA` (AHCI), `SATA RAID Enable: Disabled` (Phoenix labels — see §1).
> - OMV 8.3.1-2 (Synchrony) installed on the Goodram C40. Hostname **`omv`**, domain **`cloud5.ovh`**
>   (FQDN `omv.cloud5.ovh`). Data drives disconnected during install; partition target = Goodram only.
> - Interface: live/default-route NIC is **`enp14s0`** (Broadcom BCM5722, matches SystemRescue naming). The
>   install-time boot banner briefly showed `enp5s0` (PCI enumeration at first boot) — trust `enp14s0`.
> - Network: `ip route` confirms the NAS is on the homelab net — DHCP `192.168.2.165`, gw `192.168.2.1`.
>   The `192.168.178.15` on the banner was the install-time boot on a different (Fritz!Box-style) network — stale.
> - Static IP applied: `192.168.2.210`/24, gw `192.168.2.1`, DNS `192.168.2.1`, on `enp14s0` (§4c).
> - HTTPS hardening: web UI is HTTPS-only — SSL/TLS enabled, self-signed cert `/C=PL/CN=192.168.2.210`,
>   Force SSL/TLS (HTTP → 301 to HTTPS) (§4d).
> - Arrays + filesystems created (§5): `md0` (2× 500 GB Hitachis → XFS) and `md1` (2× 250 GB → ext4),
>   mounted by OMV under `/srv/dev-disk-by-uuid-*`. SSH root access verified (`ssh root@192.168.2.210`).
>   Note: fresh `md0` reports ~9 GB used — verified as XFS metadata (`du` = 0 B, see §5 Filesystems gotcha).
> - RAID UI plugin: OMV 8 has **no RAID page in the base install** — the `openmediavault-md`
>   plugin (8.1.5-1) had to be installed first; OMV upgraded 8.3.1 → 8.5.6-1 in the process (see §5).
> - Dashboard: all widgets enabled on the home dashboard via `Dashboard | Settings` (§6, executed after RAID).
> - SSH: user **`jarek`** created via web UI (`_ssh`, `sudo`, `users`, `openmediavault-admin`,
>   `openmediavault-webgui`), workstation `lenovo-slim` pubkey attached. Hardening applied via
>   `Services | SSH`: key-only, LAN-only (`Match Address`), root console-only (§8, 2026-08-15).
> - Disk noise tuning: **AAM = quietest** (`Minimum performance, minimum acoustic output`) set on
>   all 4 data drives via `Storage | Disks → Edit`, applied 2026-08-15 (§6). APM and Spindown
>   deliberately left `Disabled` (RAID-safety + wear — see §6 / research 23).
> - System update: **29 stable/security packages** upgraded via `apt` (util-linux security fix,
>   postfix, chrony, rsync, Python 3.13, etc.). Backports kernel 7.1.3 + ~23 firmware packages
>   deliberately skipped (§6, 2026-08-15).
> - Backports repo disabled: `openmediavault-kernel-backports.list` commented out via `sed`;
>   `apt update` → "All packages are up to date.", Updates page shows 0 (§6, 2026-08-15).

---

## Prerequisites

### Access

There is **no out-of-band management** on this ML110 G5: the LO100 expansion-card slot is
empty and the management RJ45 port is fused with a metal plate (research 23). All steps run
from a **keyboard + mouse + monitor** attached directly to the box.

### Hardware state (from research 23 — hardware inventory)

| # | Drive | Serial | Role |
|---|---|---|---|
| 3 | Hitachi HDS721050CLA660 500 GB | `JP1572FL1849SK` | `md0` |
| 4 | Hitachi HDS721050CLA660 500 GB | `JP1572FL167V6K` | `md0` mirror |
| 5 | WDC WD2500AAKX 250 GB | `WD-WCC2F0157761` | `md1` |
| 6 | GB0250EAFYK 250 GB | `WCAT1F035986` | `md1` mirror |
| 7 | **Goodram C40 120 GB SSD** | `1C9C074614D500572350` | **OMV OS** |
| 8 | WDC WD10EZEX 1 TB (spare) | `WD-WCC3F7AKKXUT` | **offline** — reviewed 2026-08-15, content not documented (§7) |

### Media & tools

- **OMV 8.x ISO** — download from [SourceForge](https://sourceforge.net/projects/openmediavault/files/).
- **Bootable USB stick** — reuse the **YUMI** multi-boot stick (flash the ISO onto it), or write
  with `dd`/Etcher. The ML110 is BIOS-only; no UEFI requirement.
- The **Dell SAS 6/iR** is already **removed** (research 23) — no hardware RAID anywhere.

> ⚠ **Disconnect the 4 data drives during install.** The OMV 8.x installer is minimal-interaction
> and **auto-picks the first disk it finds** for the OS. Disconnect drives #3–#6 so the installer
> targets the Goodram SSD. Reconnect them after first boot (§5).

---

## 1. BIOS Configuration

Enter BIOS during POST (typically `F8`/`F9`/`Del` on ML110 models) and set:

> **HP Phoenix label mapping (verified 2026-08-09).** The SATA options live under
> `Advanced | Advanced Chipset Control | Serial ATA` and use HP-specific names:
> `Serial ATA` (controller on/off), `Native Mode Operation` (mode selector — **`Serial ATA`** = AHCI,
> `Auto` = legacy IDE), `SATA RAID Enable` (ICH9R RAID firmware).

| Setting | Current | Target |
|---|---|---|
| Serial ATA | enabled | **`Enabled`** |
| Native Mode Operation (= SATA Controller Mode → AHCI) | `IDE` (ICH9R `00:1f.2` + ICH9 `00:1f.5`) | **`Serial ATA`** |
| SATA RAID Enable (= ICH9R RAID firmware) | enabled | **`Disabled`** (raw disks to mdadm) |
| Boot Mode | BIOS | **`BIOS`** (OMV ISO is BIOS-only) |
| Secure Boot | N/A (G5) | `Off` |
| Boot order | USB first (temporary) | **Goodram C40 SSD first** (after install) |
| Network boot | PXE (also RPL, BOOTP) | `Disabled` for local install |

> Only the Goodram SSD should stay attached for the first boot sequence (data drives still
> disconnected from the prerequisites). Take a **photo** of the AHCI/RAID BIOS screen before
> applying (photo for the record).

---

## 2. Flash the OMV 8.x ISO to USB

1. Download the latest **OMV 8.x** ISO (Debian 13 base).
2. Reuse the **YUMI** stick: add the OMV ISO to the multi-boot menu, or replace it with a
   dedicated stick:
   ```sh
   sudo dd if=openmediavault_*.iso of=/dev/sdX bs=4096 status=progress
   ```
3. Boot the ML110 from the USB stick.

---

## 3. Install OMV 8.x on the Goodram SSD

With **only the Goodram SSD attached** (data drives disconnected):

1. Boot the ISO → the installer is minimal-interaction: prompts for **location**, **language**,
   and **root password**.
2. The OS deploys to the **first disk found** — the Goodram SSD (wiping the old Ubuntu LVM).
   Record the root password for post-install SSH / CLI.
3. On completion the machine reboots — **remove the USB stick**.
4. The console login screen shows the **DHCP-assigned IP** for the web UI. Note it; the static
   IP is set in §4.

> **SSH note:** OMV enables SSH for `root` by default. Disable it under
> `Services | SSH` after setup (see OMV docs), keeping root access via a `sudo` user.

---

## 4. Post-Install: Web UI, Time, Static IP

### 4a. First login

- Browse to the DHCP IP shown on the console.
- Login: `admin` / `openmediavault` (default). Change the admin password immediately
  (`System | Settings | Web Administration`).

### 4b. NTP + timezone (RTC drifts ~13 days — research 23)

- `System | Date & Time` — set **timezone** and enable **NTP**.
- The G5 RTC loses time across reboots; NTP corrects it.
- **The CR2032 CMOS battery is dead** (confirmed 2026-08-15): unplugging power resets the clock
  **and** reverts BIOS settings to defaults (boot device order, AHCI/RAID mode). **Replace the
  CR2032** (standard coin cell, ~5–10 PLN) and re-apply the §1 BIOS settings (AHCI, RAID off,
  boot from the Goodram SSD) after the swap.

### 4c. Static IP `192.168.2.210`

Per [research 24 — network topology](../research/24-network-topology-design.md), the NAS owns
`192.168.2.210` on the homelab subnet (TL-SG108E **switch port 3**):

- `Network | Interfaces` → edit `enp14s0` (Broadcom BCM5722, MAC `78:e7:d1:53:fb:87`).
- Method: **Static** — IP `192.168.2.210`, netmask `255.255.255.0`, gateway `192.168.2.1`.
- Apply. Verify from the M910q (§6). Update the switch port mapping if needed (runbook 23).
- **Web UI:** [`Network | Interfaces`](https://192.168.2.210/#/network/interfaces)

> **Network status (2026-08-09, resolved).** `ip route` on the NAS confirms it is on the homelab net:
> DHCP `192.168.2.165`, gw `192.168.2.1`, dev `enp14s0`. The `192.168.178.15` on the first-boot banner was
> a stale/install-time lease from a different network (Fritz!Box-style `178.0/24`); it does not reflect
> the current attachment. Safe to apply the static `192.168.2.210` now.

### 4d. HTTPS-only web UI (deviation from plan — added 2026-08-09)

Per user request the web UI is HTTPS-only. `System | Workbench | Settings`:

| Setting | Value |
|---|---|
| SSL/TLS enabled | ✅ |
| Certificate | self-signed `/C=PL/CN=192.168.2.210` (created under `System \| Certificates \| SSL` → Create) |
| HTTPS port | `443` |
| Force SSL/TLS | ✅ — HTTP on port 80 only 301-redirects to HTTPS |

- **Web UI:** [`System | Certificates | SSL`](https://192.168.2.210/#/system/certificate/ssl) (create/import cert) · [`System | Workbench | Settings`](https://192.168.2.210/#/system/workbench/settings) (HTTPS/SSL/TLS config)
- Access the UI at **`https://192.168.2.210`**; accept the self-signed cert on first visit (one-time per
  browser). Cert valid 1 year — renew under `System | Certificates` (or re-create).
- OMV 8 rejects HTTP port `0` (valid range 1–65535), so the HTTP listener can't be fully removed via
  the UI; `Force SSL/TLS` achieves "no plaintext served" via redirect.
- When `omv.cloud5.ovh` is exposed via the Cloudflare Tunnel (Phase 2, [§9](#9-expose-the-omv-web-ui-via-cloudflare-tunnel-phase-2)), TLS terminates at the edge with
  a proper cert; this self-signed cert only serves direct LAN access.

---

## 5. Create mdadm RAID1 Arrays

Reconnect the **4 data drives** (#3–#6) to the onboard ICH9R SATA ports (§Prerequisites).

> **⚠ First: install the `openmediavault-md` plugin.** In OMV 8, the **Software RAID UI is a
> separate plugin, not part of the base install** — a fresh OMV has no RAID page at all.
> `System | Plugins` → search `md` → install **`openmediavault-md`** (this may also upgrade OMV
> itself, e.g. 8.3.x → 8.5.x). Then do a **full page reload** so the `Storage | Multiple Device`
> entry appears in the navigation.

> **What OMV's RAID page actually is.** OMV has no RAID engine of its own — `Storage | Multiple Device`
> (route `#/storage/md`) is a GUI wrapper around **`mdadm`**. Creating an array in the UI runs
> `mdadm --create`, producing a standard Linux `/dev/md*` device; OMV then maintains
> `/etc/mdadm/mdadm.conf` so arrays auto-assemble at boot, and owns the mount management for the
> filesystems you build on top (XFS/ext4) via `Storage | File Systems`. The arrays are genuine
> Linux software RAID — portable to any Linux box, per-disk SMART intact. (See [research 23](../research/23-ml110-nas-omv.md).)

OMV manages mdadm in the web UI (`Storage | Multiple Device`). It works best with **unpartitioned raw
block devices** — wipe the disks first if they carry old signatures:

1. `Storage | Disks` — for each of the 4 data drives: **Wipe** (quick wipe is enough to clear
   partition tables; full wipe if old RAID superblocks are present).
2. `Storage | Multiple Device` → **Create** — **Level 1 (Mirror)**:
   - Select the two **Hitachi 500 GB** drives (match by **serial** — the 500 GB Hitachis share a
     model, only serial distinguishes them) → `md0`.
   - Create a second array: the two **250 GB** drives (WDC WD2500AAKX + GB0250EAFYK) → `md1`.
3. Wait for the initial resync. Optionally speed it up:
   ```sh
   echo 50000 > /proc/sys/dev/raid/speed_limit_min
   ```

### Filesystems

`Storage | File Systems` → **Create**:

| Device | Filesystem | Mount point (OMV auto) |
|---|---|---|
| `md0` (500 GB usable) | **XFS** | `/srv/dev-disk-by-uuid-*` (auto) |
| `md1` (250 GB usable) | **ext4** | `/srv/dev-disk-by-uuid-*` (auto) |

> **Gotcha — a fresh XFS shows ~9 GB used immediately.** `mkfs.xfs` with the modern feature set
> OMV enables (`rmapbt=1`, `reflink=1`, `bigtime=1`, `nrext64=1`) pre-builds its reverse-mapping
> and refcount B-trees across the whole volume, so a brand-new ~466 GB array reports **~9 GB used
> (~2%)** with an empty mount point. This is **filesystem metadata, not data** — it does not grow
> with normal writes and is harmless. Verify with `du -sh /srv/dev-disk-by-uuid-*` (shows ~0 while
> `df` shows the used bytes). Compare: fresh ext4 (`md1`) reports only ~2 MiB used — ext4 doesn't
> pre-build that metadata. Do not reclaim it by re-creating the FS without `reflink`/`rmapbt`; the
> 2% cost isn't worth touching a working RAID array.

OMV integrates the filesystems into its DB (no manual `/etc/fstab` edits — OMV owns mount
management). Shared folders / exports are **Phase 2** (issue #62) — not created here.

---

## 6. Verify

```sh
# Arrays assembled
cat /proc/mdstat

# Per-array detail
mdadm --detail /dev/md0
mdadm --detail /dev/md1

# Filesystems mounted by OMV
mount | grep -E 'md0|md1'
```

**Reboot persistence check:** `sudo reboot`, then re-verify `md0`/`md1` are auto-assembled and
mounted. This is the key resilience test for a backup target.

**From the M910q (homelab server):**

```sh
ping 192.168.2.210            # static IP reachable
```

**Web UI:** `https://192.168.2.210` loads and shows both arrays as clean in `Storage | Multiple Device`.

### Dashboard widgets (customization — 2026-08-09)

`Dashboard | Settings` — all available widgets enabled for the home dashboard
([`#/dashboard/settings`](https://192.168.2.210/#/dashboard/settings)):

| Widget | Shows |
|---|---|
| CPU · CPU Utilization · Load Average | processor load |
| Memory | RAM usage |
| Uptime · System Time | clock/uptime |
| System Information · Updates Available · Help | box facts, pending updates, docs links |
| Disk Temperatures · S.M.A.R.T. Status | per-disk health/thermals |
| MD Devices | software RAID array state |
| File Systems (table + grid) | mounted filesystems two ways |
| Network Interfaces (table + grid) | NIC status two ways |
| Services (table + grid) | running services two ways |

Default settings elsewhere untouched (auto-logout etc. left as-is).

### Disk acoustic & power management (AAM/APM — applied 2026-08-15)

Noise is the biggest concern on this box, so AAM is set to **quietest** on all 4 data drives
(the 2× Hitachi 500 GB + WD2500AAKX + GB0250EAFYK — *not* the Goodram OS SSD).
`Storage | Disks` → select a data drive → **Edit** → **Advanced Acoustic Management** →
**Minimum performance, minimum acoustic output** → Save (repeat per drive) → **Apply**.

> Match drives by **serial**, not `/dev/sdX` — OMV device letters shift across reboots/SCSI
> enumeration (2026-08-15: sda=Hitachi JP1572FL1849SK, sdb=WD2500AAKX, sdc=Goodram SSD,
> sdd=GB0250EAFYK, sde=Hitachi JP1572FL167V6K).

| OMV device (2026-08-15) | Drive | Serial | AAM |
|---|---|---|---|
| `/dev/sda` | Hitachi HDS721050CLA660 | `JP1572FL1849SK` | 🔇 quietest |
| `/dev/sdb` | WDC WD2500AAKX | `WD-WCC2F0157761` | 🔇 quietest |
| `/dev/sdd` | GB0250EAFYK | `WCAT1F035986` | 🔇 quietest |
| `/dev/sde` | Hitachi HDS721050CLA660 | `JP1572FL167V6K` | 🔇 quietest |
| `/dev/sdc` | Goodram C40 SSD | `1C9C074614D500572350` | n/a (SSD) |

**Deliberately not set** (full AAM/APM analysis in [research 23](../research/23-ml110-nas-omv.md)):

- **APM** — left `Disabled`. The only RAID-safe value (≥128) doesn't spin down but adds head
  load/unload cycles (wear) for marginal power saving; it doesn't reduce the hum.
- **Spindown time** — left `Disabled`. Never spin down RAID members: mdadm can mark a
  slow-to-wake drive as **failed** → array degradation.

Verify (`hdparm` needs root):

```sh
sudo hdparm -M /dev/sda /dev/sdb /dev/sdd /dev/sde   # expect: acoustic = 128 (minimum)
```

### System update — stable/security batch (applied 2026-08-15)

Routine Debian patching via SSH (`sudo apt install …`). **29 packages upgraded**, all from
Debian **stable / security / stable-updates** — the important one is the **util-linux security
fix** (`util-linux`, `mount`, `login`, `fdisk`, `bsdutils` + libs), plus `postfix` (security),
`chrony`, `rsync`, `libcurl`, `xz`, `libxml2`, `base-files`, Python 3.13.5-2+deb13u4, etc.

**Deliberately NOT installed** — the **backports kernel 6.12 → 7.1.3** and the **~23 backports
firmware packages** (~230 MiB of firmware for hardware this box doesn't have). The stock Debian
6.12 kernel is what OMV 8 is built/tested against; a backports kernel jump adds risk + a reboot
for zero benefit on this hardware. The `trixie-backports` repo was then **disabled** (see below),
so the ~29 backports suggestions no longer appear at all.

- `postfix` chose **No configuration** during install → OMV keeps owning its config
  (`main.cf` untouched by debconf). `postfix`/`rsync` services stay inactive until OMV enables
  them (notifications / rsync plugin, Phase 2) — expected.
- No reboot required (userspace-only, no kernel touched).

### Backports repo disabled (applied 2026-08-15)

The `openmediavault-kernel-backports` file (created by OMV so the backports kernel is available)
was **commented out** — OMV's Updates page lists *whatever the enabled repos offer*, it does not
recommend per-package, and Debian's own stance is "newer, not necessarily more stable". For a
backup-target NAS on fully-supported hardware (E2160, ICH9R, BCM5722), the backports kernel
+ 230 MiB of firmware for absent hardware are risk/noise with zero upside.

```sh
sudo sed -i 's/^deb /#deb /' /etc/apt/sources.list.d/openmediavault-kernel-backports.list
sudo apt update          # → "All packages are up to date."; Updates page shows 0
```

- **Reversible** — the `deb` line is only commented; uncomment to re-enable the backports kernel.
- **May re-appear** — an upgrade/reinstall of the `openmediavault-kernel-backports` package can
  re-create the file; re-run the same `sed`, or `apt remove openmediavault-kernel-backports` if it recurs.

---

## 7. Review the 1 TB WD10EZEX Spare — **done (offline)**

> **Done 2026-08-15.** The WD10EZEX (`WD-WCC3F7AKKXUT`) content was reviewed via SystemRescue.
> **Role decision: offline** — the drive stays disconnected for now (ICH9 port #6 free). Its
> contents are **deliberately not documented** — they include personal data and this repository is
> public (per the repo's sanitization rule). The decision is recorded in
> [research 23](../research/23-ml110-nas-omv.md).

---

## 8. Wrap-up

- Confirm acceptance criteria from issue #61:
  - OMV web UI reachable at `https://192.168.2.210` (HTTPS-only, §4d).
  - Data pool online with redundancy (`md0` + `md1`, clean).
  - Arrays survive reboot — **confirmed** (auto-assembled + mounted after reboot).
  - Static IP `192.168.2.210` verified from the M910q.
- The **NFS `/export/backups`** and **SMB `/shared`** exports are **Phase 2** (issue #62).
- Mark the idea 03 status → **🔨 Implementing** (then **✅ Done**) in
  `docs/ideas/03-nas-backup-target-ml110.md` and `docs/ideas/README.md`.
- Report completion on issue #61 (and #62 once exports are live) so the parent #54 can close.

### SSH access — workstation (user `jarek`, via web UI)

Key-based SSH for the operator (and `sudo` admin) is done **via the OMV web UI**, not at the CLI.
The NAS is reachable directly **only from the home LAN** (`192.168.2.0/24`); nothing is exposed
outside it (see the hardening block below — applied, not deferred).

1. **Create the operator user** — `Users | Users` → **Create**: name `jarek`, assign groups
   **`_ssh`** (SSH login), **`sudo`**, **`users`**, and — for full web-UI admin —
   **`openmediavault-admin`** + **`openmediavault-webgui`**. Set a password.
   (The built-in `admin` is the web-GUI bootstrap account; `jarek` is the operator's daily
   SSH + admin identity.)
2. **Add the workstation public key** — edit the user → **SSH public keys** → **Add** and paste
   the workstation `id_ed25519.pub` (`lenovo-slim`, already in use across the homelab, runbook 1).
   OMV converts it to RFC 4716 for `authorized_keys`.
3. **Apply** the pending config changes (`postfix`, `ssh` modules).
4. **Verify** from the workstation: `ssh jarek@192.168.2.210` logs in **without** a password
   (`jarek` has `sudo` for admin tasks; `ssh jarek@omv` also works via the `~/.ssh/config` alias).

> **No home directory is created by OMV** — `/home/jarek` is absent until created at the CLI
> (`mkdir -p /home/jarek && chown jarek:users /home/jarek && chmod 755 /home/jarek`). Harmless
> (only a chdir warning on login). Optionally, once shared folders exist (Phase 2, issue #62),
> `Users | Settings` → **User home directory** can place homes on the data pool instead.

### SSH hardening (applied 2026-08-15)

`Services | SSH`:

| Setting | Value |
|---|---|
| Enabled | ✅ |
| Port | `22` |
| Permit root login | ❌ — root is **console-only** (no SSH as root) |
| Password authentication | ❌ — key-only |
| Public key authentication | ✅ |
| Extra options | `Match Address !192.168.2.0/24` → `DenyUsers *` (LAN-only) |

- **Key-only** — `PasswordAuthentication` off; `jarek` uses the installed pubkey.
- **LAN-only** — the `Match Address` block denies SSH from outside `192.168.2.0/24`. (UFW
  `allow from 192.168.2.0/24 to any port 22` is an alternative if the firewall plugin is used.)
- **Root is console-only** — root SSH is disabled; admin work happens via `jarek` + `sudo`.
- SSH is **never** exposed via the Cloudflare Tunnel (see §9) — do not route it through.

---

## 9. Expose the OMV Web UI via Cloudflare Tunnel (Phase 2)

> **⛔ Blocked by [#65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65).**
> Public ingress is moving off the M910q onto a dedicated edge box (ADR 24 / idea 04). This step
> is **deferred until #65 lands** — do not add the `omv` hostname to the M910q tunnel yet, since
> the tunnel/Caddy configuration is being re-architected there.

The NAS stays **storage-only** — no `cloudflared` runs on it (ADR 23). Public access reuses
the homelab tunnel (currently on the M910q; **moving to the dedicated edge device via #65**)
and routes through Caddy, the single routing layer (ADR 20).

1. **Add an `omv` public hostname** in the Cloudflare Zero Trust portal
   (Networks → Tunnels → `homelab-tunnel` → **Public Hostname** → **Add a public hostname**):

   | Field | Value |
   |---|---|
   | Subdomain | `omv` |
   | Domain | `cloud5.ovh` |
   | Type | `HTTP` |
   | URL | `caddy:80` |

   (Or rely on the existing wildcard `*.cloud5.ovh → http://caddy:80` — ADR 20 keeps the
   tunnel as TLS-termination-only; all per-service routing lives in the Caddyfile.)

2. **Add a Caddy site block** on the M910q (`/opt/docker/Caddyfile`):

   ```Caddyfile
   omv.cloud5.ovh {
       reverse_proxy https://192.168.2.210 {
           tls_insecure_skip_verify
           header_up X-Forwarded-Proto https
       }
   }
   ```

   OMV serves HTTPS-only (§4d) with a self-signed cert, so Caddy proxies to the HTTPS origin
   and skips origin verification (same HTTPS-origin caveat as ADR 19).

3. **Reload Caddy** on the M910q: `docker compose restart caddy`.

4. **Verify externally**: `https://omv.cloud5.ovh` loads the OMV login page (Cloudflare edge
   TLS — no self-signed warning). SSH is never exposed through the tunnel (§8).

---

## Troubleshooting

- **GRUB fails to install (`Unable to install GRUB in /dev/sda`)** — from the OMV installer
  menu select *Execute a shell*:
  ```sh
  chroot /target
  grub-install /dev/sdX      # the Goodram SSD
  update-grub
  exit
  exit
  ```
  Then *Continue without boot loader* in the Debian installer.
- **Drives not visible after reconnect** — confirm they are on the onboard ICH9R SATA ports
  (`00:1f.2`) and that BIOS SATA mode is **AHCI**, not RAID/IDE (mdadm needs raw disks).
- **RTC/time wrong or BIOS settings reset after power-off** — the **CR2032 CMOS battery is dead**
  (confirmed 2026-08-15). NTP corrects the clock once booted (§4b), but BIOS settings revert to
  defaults on power loss — **replace the CR2032** and re-apply the §1 settings (AHCI, RAID off,
  boot from the Goodram SSD).
- **Web UI unavailable after static IP** — the DHCP lease was replaced; use the console to
  confirm the interface came up with `192.168.2.210` (`ip a show enp14s0`).

---

## References

- [Research 23 — ML110 NAS (OMV)](../research/23-ml110-nas-omv.md) — hardware/software trade-off analysis
- [Research 24 — network topology design](../research/24-network-topology-design.md) — static IP `192.168.2.210`
- [Idea 03 — Homelab NAS on ML110](../ideas/03-nas-backup-target-ml110.md)
- [ADR 23 — NAS on ML110](../decisions/23-nas-on-ml110.md)
- [OMV 8.x — Installation via ISO](https://docs.openmediavault.org/en/8.x/installation/via_iso.html)
- [OMV 8.x — Storage / RAID](https://docs.openmediavault.org/en/8.x/administration/storage/raid.html)
- Issue [#61](https://github.com/jaroslaw-bagnicki/Homelab/issues/61) — Phase 1 (this runbook)
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) — parent issue
