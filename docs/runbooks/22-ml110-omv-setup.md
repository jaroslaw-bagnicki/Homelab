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
- [ ] NTP + timezone set
- [ ] `md0` (2× 500 GB → XFS) online
- [ ] `md1` (2× 250 GB → ext4) online
- [ ] Arrays survive reboot
- [ ] 1 TB spare content reviewed, role decided
- [ ] Static IP `192.168.2.210` set and verified from the M910q
- [ ] OMV web UI reachable at `https://192.168.2.210` (HTTPS-only, §4d)

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
| 8 | WDC WD10EZEX 1 TB (spare) | `WD-WCC3F7AKKXUT` | unplugged — content review §7 |

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
> applying (inventory §9 photo checklist).

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
- The G5 RTC loses time across reboots; NTP corrects it. **Consider swapping the CR2032
  CMOS battery** to reduce drift (research 23 notes).

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
- When `omv.cloud5.ovh` is exposed via the Cloudflare Tunnel (Phase 2), TLS terminates at the edge with
  a proper cert; this self-signed cert only serves direct LAN access.

---

## 5. Create mdadm RAID1 Arrays

Reconnect the **4 data drives** (#3–#6) to the onboard ICH9R SATA ports (§Prerequisites).

> **What OMV's RAID page actually is.** OMV has no RAID engine of its own — `Storage | RAID`
> is a GUI wrapper around **`mdadm`**. Creating an array in the UI runs `mdadm --create`,
> producing a standard Linux `/dev/md*` device; OMV then maintains `/etc/mdadm/mdadm.conf`
> so arrays auto-assemble at boot, and owns the mount management for the filesystems you
> build on top (XFS/ext4) via `Storage | File Systems`. The arrays are genuine Linux software
> RAID — portable to any Linux box, per-disk SMART intact. (See [research 23](../research/23-ml110-nas-omv.md).)

OMV manages mdadm in the web UI (`Storage | RAID`). It works best with **unpartitioned raw
block devices** — wipe the disks first if they carry old signatures:

1. `Storage | Disks` — for each of the 4 data drives: **Wipe** (quick wipe is enough to clear
   partition tables; full wipe if old RAID superblocks are present).
2. `Storage | RAID` → **Create** — **Level 1 (Mirror)**:
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

**Web UI:** `http://192.168.2.210` loads and shows both arrays as clean in `Storage | RAID`.

---

## 7. Review the 1 TB WD10EZEX Spare

1. Power off, connect the **WD10EZEX** (`WD-WCC3F7AKKXUT`) to the free ICH9 port **#6**.
2. Power on and inspect its existing content before assigning any role:
   ```sh
   lsblk -f /dev/sdX          # existing partitions / filesystems
   sudo mkdir /mnt/review && sudo mount /dev/sdX1 /mnt/review && ls /mnt/review
   ```
3. Decide its role:
   - **Bulk volume** — if it holds media/archives worth keeping, add as a single-disk XFS
     volume (via OMV `Storage | File Systems`) or an `mdadm` member.
   - **Offline** — per research 23, the drive is **unplugged for now**; if the content is
     redundant, leave it disconnected and record the decision in the inventory.
4. Record the outcome in [research 23](../research/23-ml110-nas-omv.md) (open question #3).

---

## 8. Wrap-up

- Confirm acceptance criteria from issue #61:
  - OMV web UI reachable at `http://192.168.2.210`.
  - Data pool online with redundancy (`md0` + `md1`, clean).
  - Arrays survive reboot.
- The **NFS `/export/backups`** and **SMB `/shared`** exports are **Phase 2** (issue #62).
- Mark the idea 03 status → **🔨 Implementing** (then **✅ Done**) in
  `docs/ideas/03-nas-backup-target-ml110.md` and `docs/ideas/README.md`.
- Report completion on issue #61 (and #62 once exports are live) so the parent #54 can close.

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
- **RTC/time wrong after reboot** — NTP is enabled (§4b); if drift persists, replace the
  CR2032.
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
