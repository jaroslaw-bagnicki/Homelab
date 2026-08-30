# Edge Appliance (Wyse 3040) — Backup & Restore

> Full-system image backup/restore of the edge appliance's eMMC to the ML110 NAS.
> Baseline image taken **2026-08-22** (issue [#79](https://github.com/jaroslaw-bagnicki/Homelab/issues/79)).
> **Current backup (2026-08-30)**: bundle `\\omv\edge\wyse3040-20260830-125805\`
> (= `Z:\edge\wyse3040-20260830-125805\`), run logs in `\\omv\edge\wyse3040-20260830-125805\logs\`
> (= `Z:\edge\wyse3040-20260830-125805\logs\`).
> **First choice: Clonezilla** (`ocs-sr savedisk`/`restoredisk`) — whole-disk image incl. GPT
> partition table + all partitions, only used data, full wipe→restore→boot cycle validated on
> the 3040 (2026-08-24).
> **Fallback: `dd` + `gzip`** (proven wipe→restore cycle, 2026-08-23). Images stored on the OMV
> SMB share.

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
- **Clonezilla tooling**: the current **Rescuezilla** live ISO bundles both `ocs-sr` and
  `mount.cifs` — no separate Clonezilla live USB needed (verified 2026-08-24).

## Known gotchas (Wyse 3040 eMMC)

| # | Gotcha | Workaround |
|---|---|---|
| 1 | eMMC block device missing in live envs | `modprobe mmc_block` in the live terminal |
| 2 | Device name **shifts** between sessions (`mmcblk0` ↔ `mmcblk1`) | Always `lsblk` first; never hardcode |
| 3 | Some live kernels don't enumerate it at all (SystemRescue, Clonezilla) | Use Debian-based live media (installer proved it works) + `modprobe mmc_block` |
| 4 | **Rescuezilla GUI crashes** with `UnicodeDecodeError: … byte 0x92` | The eMMC model string (`H8G4a\x92`) contains a non-UTF-8 byte; Rescuezilla's Python parses it at the partition-table step. **Workaround: use the terminal `ocs-sr`/`dd` flow, not the GUI** |
| 5 | **Unplugging the boot USB mid-session** breaks the live FS (I/O errors; `mount.cifs` then fails with `failed to execute /sbin/mount.cifs`) | Leave the stick in until the run is done; reboot to recover |
| 6 | Clonezilla image dir is hardwired to `/home/partimag` — the `-s /mnt/backup` override **did not work** here | `mkdir -p /home/partimag` and mount the NAS **at `/home/partimag`** |
| 7 | `jq` missing in Rescuezilla → `ocs-sr` prints `jq: command not found`, disk info shows `No_size\|No_Model` | Cosmetic only; does not affect the image |
| 8 | eMMC SMART not readable in live env (`smartctl: Unable to detect device type`) | No health telemetry from the live session; treat the earlier full-`dd` read as the integrity probe |

> ⚠ The `0x92` byte and the live-media enumeration gap are the same quirks documented in
> [research 28](../research/28-wyse3040-hardware-diagnostic.md) — they apply to any non-Debian
> live tooling on this box.

## Access the pendrive (Ventoy mapper)

The YUMI/Ventoy stick boots the live ISO and also carries the backup checklist
(`clonezilla-usage.txt`). In the live session the stick is **not auto-mounted**, and because
it's a Ventoy stick its data partition is claimed by the device-mapper — mounting the raw
`/dev/sda2` fails with **"busy"** (and 32 M `sda2` is the tiny VTOYEFI partition anyway, not
your files). Mount the mapper node instead:

```sh
lsblk                       # data partition = the big sda1 (57.7 G); sda2 (32 M) is VTOYEFI, NOT it
ls -l /dev/mapper/          # sda1 -> ../dm-X (data), ventoy -> ../dm-X (vtoys, mounted at /cdrom)
mkdir -p /mnt/usb
mount /dev/dm-1 /mnt/usb    # the dm node that maps the DATA partition — confirm the number first
ls /mnt/usb                 # → YUMI/Data/Wyse 3040/clonezilla-usage.txt
```

> The `dm-*` number is **session-dependent** (the data partition was `dm-1` on 2026-08-30) —
> always confirm it with `lsblk` / `ls -l /dev/mapper/` first. When the named node exists,
> prefer it: `mount /dev/mapper/sda1 /mnt/usb`.

## Which tool — comparison (measured on the 3040, 2026-08-24)

| | Clonezilla `savedisk` | `dd` + `gzip` |
|---|---|---|
| Image size | ~456 MB | ~611–614 MB |
| Time | ~40 s save (+ ~56 s check) | ~177 s (~3 min) |
| Coverage | Used data + GPT partition table | Full raw 7.8 GB (every sector) |
| Verify | Built-in "restorable" check | Manual (ISIZE / `gzip -l`) |
| Restore tested | ✅ proven | ✅ proven |

Clonezilla is first choice: self-describing image (partition table saved), built-in
verification, and faster restore. The size/time gap on this small eMMC is modest — the
deciding factor is the clean restore workflow.

## Clonezilla — first choice

### Backup (`savedisk`)

Boot the live USB (F12) → open a terminal (root):

```sh
# 1. Make the eMMC visible (fresh live session)
modprobe mmc_block

# 2. Confirm the device name (may be mmcblk0 or mmcblk1!)
lsblk

# 3. Mount the NAS AT /home/partimag (Clonezilla's hardwired image dir —
#    the -s override did NOT work on this box; see gotcha 6).
#    Mount the edge/ subfolder so images + logs stay under shared/edge/,
#    matching the dd layout. mount.cifs prompts for the password.
mkdir -p /home/partimag /var/log/clonezilla
mount -t cifs //192.168.2.210/shared/edge /home/partimag -o username=rescuezilla,vers=3.1.1,seal

# 3b. Persist Clonezilla logs on the NAS — they default to RAM-only
#    /var/log/clonezilla and are lost on reboot. Pre-create <bundle>/logs and
#    bind-mount it, so logs stream straight into the right location.
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p /home/partimag/wyse3040-$TS/logs
mount --bind /home/partimag/wyse3040-$TS/logs /var/log/clonezilla

# 4. Whole-disk image, timestamped (saves GPT partition table + both partitions,
#    only used data). Image lands at /home/partimag/wyse3040-<ts>/
#    (= shared/edge/wyse3040-<ts>/ on the NAS).
#    (no -i 0: it is ignored in this build — the image check runs anyway)
ocs-sr -q2 -c -z1p savedisk wyse3040-$TS mmcblk0

# 5. (done — logs already landed at \\omv\edge\wyse3040-20260830-125805\logs\ during the run)
```

**Expected**: ~40 s; image ≈ 456 MB for ~1.3 GB used. Output shows both partitions cloned
and **"restorable"** — that is the verification. The `jq: command not found` lines are
cosmetic (gotcha 7). **Do not unplug the boot USB until the run finishes** (gotcha 5).

### Restore (`restoredisk`)

**Validated end-to-end 2026-08-24** — Clonezilla wiped the destination itself (zeroed the MBR,
recreated the GPT with the original GUID), restored both partitions (100%, partclone), rebuilt
initramfs and re-created the EFI NVRAM boot entry (clean logs), and the box **booted
successfully** from the restored eMMC (back at `192.168.2.240`, SSH OK). Full
wipe → `restoredisk` → boot cycle proven.

Boot the live USB (F12) → open a terminal (root):

```sh
# 1. eMMC visible
modprobe mmc_block
lsblk                    # note the device name

# 2. Mount the NAS at /home/partimag (edge/ subfolder; mount.cifs prompts for password)
mkdir -p /home/partimag /var/log/clonezilla
mount -t cifs //192.168.2.210/shared/edge /home/partimag -o username=rescuezilla,vers=3.1.1,seal

# 2b. Persist Clonezilla logs on the NAS — bind into the image bundle's logs/
#    dir (the backup-time logs live there too; restore logs append alongside).
mkdir -p /home/partimag/wyse3040-<timestamp>/logs
mount --bind /home/partimag/wyse3040-<timestamp>/logs /var/log/clonezilla

# 3. Restore the whole disk (partition table + partitions, only used blocks).
#    No manual wipe needed — Clonezilla cleans the destination first (zeroes
#    MBR + recreates GPT). No `-p true` — an auto-reboot is not wanted.
ocs-sr -q2 restoredisk wyse3040-<timestamp> mmcblk0

# 4. Reboot manually when ready (remove the USB first).
reboot
```

## `dd` + `gzip` — fallback

### Backup

Boot the live USB (F12) → open a terminal (root):

```sh
# 1. Make the eMMC visible (fresh live session)
modprobe mmc_block

# 2. Confirm the device name (may be mmcblk0 or mmcblk1!)
lsblk

# 3. Mount the NAS SMB share (share enforces SMB3 encryption → seal;
#    mount.cifs prompts for the password)
mkdir -p /mnt/backup
mount -t cifs //192.168.2.210/shared /mnt/backup -o username=rescuezilla,vers=3.1.1,seal

# 4. Full bit-by-bit image, timestamped, compressed, into edge/
#    (dd stderr → .img.log so the layout matches reality)
mkdir -p /mnt/backup/edge
TS=$(date +%Y%m%d-%H%M%S)
dd if=/dev/mmcblkX status=progress bs=4M 2> /mnt/backup/edge/wyse3040_$TS.img.log | gzip -1 -c > /mnt/backup/edge/wyse3040_$TS.img.gz

# 5. Verify + unmount
ls -lh /mnt/backup/edge/*.img.gz
umount /mnt/backup
```

**Expected**: ~3 min at ~40–44 MB/s (Atom x5-Z8350 does gzip + encrypted SMB). Image ≈ 600 MB
for a ~7.3 GiB disk with ~1 GB used. `records in == records out` and no I/O errors = clean copy.

### Online backup (no live USB)

Clonezilla needs unmounted partitions, so the online flow uses `dd` + `gzip`. If the box is
running and SSH-reachable, the backup can be done from the live OS — no console, no USB.
Slightly less clean than the live-session flow (the filesystem is mounted and can change
mid-read), but fine on this low-write box. Needs `cifs-utils` (§ Prerequisites):

```sh
# 1. Mount the NAS share (as root; mount.cifs prompts for the password)
sudo mkdir -p /mnt/backup
sudo mount -t cifs //192.168.2.210/shared /mnt/backup -o username=rescuezilla,vers=3.1.1,seal

# 2. dd straight to the NAS (device name confirmed with lsblk first;
#    dd stderr → .img.log so the layout matches reality)
sudo mkdir -p /mnt/backup/edge
sudo sh -c 'TS=$(date +%Y%m%d-%H%M%S); dd if=/dev/mmcblk0 bs=4M status=progress 2> /mnt/backup/edge/wyse3040_$TS.img.log | gzip -1 -c > /mnt/backup/edge/wyse3040_$TS.img.gz'

# 3. Verify + unmount
gzip -t /mnt/backup/edge/wyse3040_*.img.gz
sudo umount /mnt/backup
```

> ⚠ On this box, `mount.cifs` lives in `/sbin` (not on the non-login PATH) — call
> `/sbin/mount.cifs` or use `sudo mount` which resolves it. Verified 2026-08-23:
> first online snapshot `wyse3040_20260823-104107.img.gz` (546 MB, ~6.7 GiB raw, gzip OK).

### Restore

Boot the live USB (F12) → open a terminal (root):

```sh
# 1. eMMC visible
modprobe mmc_block
lsblk                    # note the device name

# 2. Mount the NAS share (mount.cifs prompts for the password)
mkdir -p /mnt/backup
mount -t cifs //192.168.2.210/shared /mnt/backup -o username=rescuezilla,vers=3.1.1,seal

# 3. Write the image back to the eMMC (conv=fsync flushes before dd exits)
gzip -dc /mnt/backup/edge/wyse3040_<timestamp>.img.gz | dd of=/dev/mmcblkX bs=4M status=progress conv=fsync

# 4. Flush, unmount, remove the USB, reboot
sync
umount /mnt/backup
reboot
```

> The live env may not have `reboot` on PATH — use `/usr/sbin/reboot` or `systemctl reboot`.

## Verify the archive

- **Clonezilla image** (`wyse3040-<timestamp>/`): the `ocs-sr` run itself reports both partitions
  **"restorable"** (built-in check). Spot-check the gzip stream if desired:
  `gzip -t /home/partimag/wyse3040-<timestamp>/mmcblk0p2.ext4-ptcl-img.gz`.
- **`dd` image**: images live under `/mnt/backup/edge/` — use the full path (or `cd /mnt/backup/edge` first):

```sh
gzip -t /mnt/backup/edge/wyse3040_<timestamp>.img.gz   # no output = archive is intact
gzip -l /mnt/backup/edge/wyse3040_<timestamp>.img.gz   # shows uncompressed size (≈7.8 GB raw)
```

## File layout on the NAS (`//192.168.2.210/shared/edge/`)

| File | Purpose |
|---|---|
| `wyse3040-<timestamp>/` | **Clonezilla image bundle** — `mmcblk0p1.vfat-ptcl-img.gz`, `mmcblk0p2.ext4-ptcl-img.gz`, GPT dumps, `blkid.list`, partition-table copies (prefix `mmcblk0`/`mmcblk1` varies per session) |
| `wyse3040-<timestamp>/logs/` | Clonezilla run logs for that backup, inside the bundle (clonezilla.log, partclone*, img-chk) |
| `wyse3040_<timestamp>.img.gz` | `dd` image (bit-by-bit, compressed) |
| `wyse3040_<timestamp>.img.log` | `dd` output captured at backup time |
| `edge-backup.sh` | Reusable backup snippet (mount + dd + timestamp) |

> Current backup on the NAS (2026-08-30): `\\omv\edge\wyse3040-20260830-125805\` —
> image bundle, with run logs inside at `\\omv\edge\wyse3040-20260830-125805\logs\`
> (same as `Z:\edge\wyse3040-20260830-125805\` and `Z:\edge\wyse3040-20260830-125805\logs\`).

## References

- [Runbook 24](24-edge-appliance.md) — the edge appliance itself
- [Runbook 26 — NAS exports](26-ml110-nas-exports.md) — the SMB `shared` target (nas-phase2 worktree)
- [Research 28](../research/28-wyse3040-hardware-diagnostic.md) — hardware audit + eMMC quirks
- [Issue #79](https://github.com/jaroslaw-bagnicki/Homelab/issues/79) — initial system backup
  (Clonezilla-vs-`dd` decision and validation comments)
