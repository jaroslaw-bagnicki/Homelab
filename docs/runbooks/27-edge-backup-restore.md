# Edge Appliance (Wyse 3040) — Backup & Restore

> Full-system image backup/restore of the edge appliance's eMMC to the ML110 NAS.
> Baseline image taken **2026-08-22** (issue [#79](https://github.com/jaroslaw-bagnicki/Homelab/issues/79)).
> Method settled from [Gemini research](https://share.gemini.google/5hpXJV0KC1K1) — `dd` + `gzip`
> from a live environment, stored on the OMV SMB share. Restore is the reverse pipe.

## When to use

- **Backup**: before risky changes on the box (Netdata #80, service migration #81, Ansible runs) so
  a 2-hour Expert install never has to be redone.
- **Restore**: after a botched change — boot the live USB, write the image back, reboot.

## Prerequisites

- **YUMI/Ventoy stick** with a Debian-based live ISO (**Rescuezilla** or **Debian Live / GParted Live**).
- **NAS SMB share**: `//192.168.2.210/shared` (OMV on `omv.local`, see runbook 26 — NAS exports),
  user **`rescuezilla`**.
- Backup script on the share: `//192.168.2.210/shared/edge/edge-backup.sh` (mount + dd + timestamped name).
- **`cifs-utils`** on the box mounting the share — `apt install cifs-utils` (provides `mount.cifs`).
  Installed on the edge **2026-08-23** for the online backup flow (§ Online backup).

## Known gotchas (Wyse 3040 eMMC)

| # | Gotcha | Workaround |
|---|---|---|
| 1 | eMMC block device missing in live envs | `modprobe mmc_block` in the live terminal |
| 2 | Device name **shifts** between sessions (`mmcblk0` ↔ `mmcblk1`) | Always `lsblk` first; never hardcode |
| 3 | Some live kernels don't enumerate it at all (SystemRescue, Clonezilla) | Use Debian-based live media (installer proved it works) + `modprobe mmc_block` |
| 4 | **Rescuezilla GUI crashes** with `UnicodeDecodeError: … byte 0x92` | The eMMC model string (`H8G4a\x92`) contains a non-UTF-8 byte; Rescuezilla's Python parses it at the partition-table step. **Workaround: use the terminal `dd` flow, not the GUI** |

> ⚠ The `0x92` byte and the live-media enumeration gap are the same quirks documented in
> [research 28](../research/28-wyse3040-hardware-diagnostic.md) — they apply to any non-Debian
> live tooling on this box.

## Backup

Boot the live USB (F12) → open a terminal (root):

```sh
# 1. Make the eMMC visible (fresh live session)
modprobe mmc_block

# 2. Confirm the device name (may be mmcblk0 or mmcblk1!)
lsblk

# 3. Mount the NAS SMB share (share enforces SMB3 encryption → seal)
mkdir -p /mnt/backup
mount -t cifs //192.168.2.210/shared /mnt/backup \
  -o username=rescuezilla,password=<pw>,vers=3.1.1,seal

# 4. Full bit-by-bit image, timestamped, compressed, into edge/
mkdir -p /mnt/backup/edge
dd if=/dev/mmcblkX status=progress bs=4M | gzip -1 -c \
  > /mnt/backup/edge/wyse3040_$(date +%Y%m%d-%H%M%S).img.gz

# 5. Verify + unmount
ls -lh /mnt/backup/edge/*.img.gz
umount /mnt/backup
```

**Expected**: ~3 min at ~40–44 MB/s (Atom x5-Z8350 does gzip + encrypted SMB). Image ≈ 600 MB
for a ~7.3 GiB disk with ~1 GB used. `records in == records out` and no I/O errors = clean copy.

### Online backup (no live USB)

If the box is running and SSH-reachable, the same backup can be done from the live OS —
no console, no USB. Slightly less clean than the live-session flow (the filesystem is
mounted and can change mid-read), but fine on this low-write box. Needs `cifs-utils` (§ Prerequisites):

```sh
# 1. Mount the NAS share (as root)
sudo mkdir -p /mnt/backup
sudo mount -t cifs //192.168.2.210/shared /mnt/backup \
  -o username=rescuezilla,password=<pw>,vers=3.1.1,seal

# 2. dd straight to the NAS (device name confirmed with lsblk first)
sudo mkdir -p /mnt/backup/edge
sudo sh -c 'dd if=/dev/mmcblk0 bs=4M status=progress | gzip -1 -c \
  > /mnt/backup/edge/wyse3040_$(date +%Y%m%d-%H%M%S).img.gz'

# 3. Verify + unmount
gzip -t /mnt/backup/edge/wyse3040_*.img.gz
sudo umount /mnt/backup
```

> ⚠ On this box, `mount.cifs` lives in `/sbin` (not on the non-login PATH) — call
> `/sbin/mount.cifs` or use `sudo mount` which resolves it. Verified 2026-08-23:
> first online snapshot `wyse3040_20260823-104107.img.gz` (546 MB, ~6.7 GiB raw, gzip OK).

## Restore

Boot the live USB (F12) → open a terminal (root):

```sh
# 1. eMMC visible
modprobe mmc_block
lsblk                    # note the device name

# 2. Mount the NAS share
mkdir -p /mnt/backup
mount -t cifs //192.168.2.210/shared /mnt/backup \
  -o username=rescuezilla,password=<pw>,vers=3.1.1,seal

# 3. Write the image back to the eMMC
gzip -dc /mnt/backup/edge/wyse3040_<timestamp>.img.gz | dd of=/dev/mmcblkX bs=4M status=progress

# 4. Unmount, remove the USB, reboot
umount /mnt/backup
reboot
```

> The live env may not have `reboot` on PATH — use `/usr/sbin/reboot` or `systemctl reboot`.

## Verify the archive

```sh
gzip -t wyse3040_<timestamp>.img.gz   # no output = archive is intact
gzip -l wyse3040_<timestamp>.img.gz   # shows uncompressed size (≈7.8 GB raw)
```

## File layout on the NAS (`//192.168.2.210/shared/edge/`)

| File | Purpose |
|---|---|
| `wyse3040_<timestamp>.img.gz` | The full eMMC image (bit-by-bit, compressed) |
| `wyse3040_<timestamp>.img.log` | `dd` output captured at backup time |
| `edge-backup.sh` | Reusable backup snippet (mount + dd + timestamp) |

## References

- [Runbook 24](24-edge-appliance.md) — the edge appliance itself
- [Runbook 26 — NAS exports](26-ml110-nas-exports.md) — the SMB `shared` target (nas-phase2 worktree)
- [Research 28](../research/28-wyse3040-hardware-diagnostic.md) — hardware audit + eMMC quirks
- [Issue #79](https://github.com/jaroslaw-bagnicki/Homelab/issues/79) — initial system backup
