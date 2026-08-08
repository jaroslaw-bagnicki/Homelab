# ML110 NAS — Phase 0: Hardware Inventory & RAID State Audit

> **Prerequisite for issue #54 — Set up Homelab NAS on HP ProLiant ML110 (OMV).**
> Run these steps **before** wiping the existing array. The machine is a physical HP ProLiant ML110
> that previously ran FreeNAS on a regular RAID array; this runbook captures its exact hardware and
> controller RAID state so the OMV install and disk layout decisions are grounded in real data.

## Goals

- Identify the exact ML110 generation (G5 / G6 / G7 / G10) — determines BIOS layout,
  max RAM, controller model, and SATA speed.
- Audit the existing controller RAID configuration: RAID level, member disks, virtual disk size, status.
- Inventory every disk: model, size, SMART health, which controller it hangs off.
- Capture BIOS-relevant settings: SATA mode (AHCI vs RAID), boot order, network MACs.
- Produce a **single inventory artifact** (filled template) that drives the OMV install plan.

## Status

- [ ] Runbook complete (all commands verified on FreeBSD/FreeNAS syntax)
- [ ] User has run all steps against the live ML110
- [ ] `docs/ideas/03-nas-backup-target-ml110.md` updated with ML110 inventory findings
- [ ] Issue #54 updated: Phase 0 complete

---

## Prerequisites

### Access

The FreeNAS OS on this box is likely **not bootable** and the existing array was **regular RAID**, not ZFS. Plan for physical inspection and controller BIOS capture rather than live OS commands.

You need **one** of:

- **Direct console / iLO / IPMI** — attach a keyboard + monitor, or use iLO/LO100 remote console. The HP ML110 G6/G7 has LO100 built in.
- **SSH** into the running FreeNAS box (only if it happens to boot): `ssh root@<freenas-ip>`

> If FreeNAS does boot, treat it as a bonus and still capture the controller RAID config from the controller BIOS/utility, since the array is regular RAID rather than ZFS.

### Tools (if FreeNAS boots)

FreeNAS/TrueNAS CORE ships with: `sysctl`, `zpool`, `zfs`, `geom`, `camcontrol`,
`pciconf`, `ifconfig`, `smartctl` (via `smartmontools` — may need installing).

If `smartctl` is missing: `pkg install -y smartmontools`.

If FreeNAS does **not** boot, skip these and rely on the controller utility plus an OMV/rescue USB for SMART data later.

---

## 1. Identify the ML110 Generation

The generation determines BIOS layout, RAM ceiling, and whether the B110i is a true
hardware controller or "fake RAID" firmware.

### 1a. From FreeNAS / system firmware (while the OS is alive)

```sh
# CPU model — the generation hint is in the processor name
sysctl hw.model

# BIOS/firmware version — contains the ProLiant model string
sysctl smbios.system.product
sysctl smbios.system.manufacturer
sysctl smbios.bios.version
sysctl smbios.bios.release
```

Expected outputs:
- **G5**: `Opteron` or `Xeon 34xx` (e.g. `Quad-Core AMD Opteron 2376`), product `ProLiant ML110 G5`
- **G6**: `Intel(R) Xeon(R) CPU X34xx` or `Core i3`, product `ProLiant ML110 G6`
- **G7**: `Intel(R) Xeon(R) CPU E3-12xx` or `Core i3`, product `ProLiant ML110 G7`
- **G10**: `Intel(R) Xeon(R) Scalable`, product `ProLiant ML110 Gen10`

### 1b. Physical inspection (if the OS is dead or SSH is unreachable)

- Power on and watch the **POST screen** — the model (e.g. `ProLiant ML110 G7`)
  appears at the top.
- Note the **LO100/iLO** address if present (G6 = LO100, G7 = iLO 3, G10 = iLO 5).
- Photograph the **motherboard model / product label** inside the case.
- Note the **drive bay count** and **connector types** (3.5" vs 2.5"/1.8").

---

## 2. System Specifications

Run on the FreeNAS live system (if it boots), or boot a Linux rescue USB and use
`dmidecode` / `lscpu` / `free -h` instead.

```sh
# RAM (bytes → GB = physmem / 1073741824)
sysctl hw.physmem
sysctl vm.stats.vm.v_cache_count    # buffer/cache — relevant if you plan a ZFS root

# CPU
sysctl hw.model
sysctl hw.ncpu                      # logical core count
sysctl hw.freq
sysctl hw.machine

# Firmware
sysctl smbios.bios.vendor
sysctl smbios.bios.version
sysctl smbios.bios.release
```

### 2a. Memory test (Memtest86+)

The machine is an older ML110 that sat idle for a long time, and its **4 GB RAM is
the borderline minimum for ZFS** — a marginal stick can silently corrupt a future
pool. Run a memory smoke test **before** deciding the pool layout.

1. From the SystemRescue boot menu, select **Memtest86+** (not the default entry).
2. Let it run **at least one full pass** (~30–60 min on 4 GB; a first-pass smoke
   test is acceptable for now).
3. Record the result: `PASS` / `FAIL` and the number of passes/errors.

| Memtest86+ result | Implication |
|---|---|
| PASS (≥1 full pass) | RAM OK — proceed with ZFS or mdadm |
| FAIL / any errors | Fix/replace the faulty module first; ZFS on bad RAM is a data-loss risk |

> If Memtest86+ is unavailable, a Linux `stress-ng --mem` loop is a weak alternative
> but does not test all address lines — prefer the real memory test.

---

## 3. Current RAID / Storage Configuration Capture

Since the existing array is **regular RAID** (not ZFS), capture the layout from
the RAID controller utility before wiping. This determines which disks are grouped
together and what the current virtual disk(s) look like.

### If using the Dell SAS 6/iR

1. Boot the machine and watch for the SAS 6/iR POST message (typically `Ctrl+C` or `Ctrl+R`).
2. Enter the RAID BIOS/utility.
3. Record:
   - Virtual disk(s) and their sizes
   - RAID level (0 or 1)
   - Member disks (by slot or SAS address)
   - Status (Optimal / Degraded / Failed)

### If using the HP B110i Smart Array

1. During POST, enter the B110i Option ROM (usually `F8`).
2. Record logical drives, RAID levels, and member disks.

### If FreeNAS happens to boot

You can still run the FreeBSD disk-discovery commands to correlate OS device names
with physical slots, but the authoritative layout is the controller utility above.

```sh
# All disks visible to the OS — FreeBSD geom
geom disk list

# All SCSI/SATA devices (shows controller → device mapping)
camcontrol devlist -v
```

---

## 4. Disk Inventory

For every disk, capture: model, serial, size, SMART overall health, and which
controller it's attached to.

### If FreeNAS boots

```sh
# All disks visible to the OS — FreeBSD geom
geom disk list

# All SCSI/SATA devices (shows controller → device mapping)
camcontrol devlist -v

# PCI devices (shows the SATA/RAID controllers)
pciconf -l -v | grep -i -E 'sata|raid|ahci|storage'

# Per-disk SMART — smartctl works on most USB-to-SATA and direct SATA
# /dev/da0, /dev/da1, etc. from `geom disk list`
for d in $(geom disk list | grep -E 'Geom name|Device Model|Serial Number|Size' -A1 \
           | awk '/Geom name/{print $3}'); do
    echo "=== /dev/$d ==="
    smartctl -i /dev/$d 2>/dev/null | grep -E 'Model Family|Device Model|Serial Number|User Capacity|Rotation'
    smartctl -H /dev/$d 2>/dev/null | grep -E 'test result|overall-health'
    echo
done
```

If `smartctl` can't open a device directly (e.g. USB enclosures), try:
```sh
smartctl --scan   # shows which /dev entries smartctl can talk to
```

### If FreeNAS does not boot

Boot from an OMV installer or a Linux rescue USB (e.g. SystemRescue) and run:

```sh
# List all SATA/SAS controllers and attached disks
lspci | grep -iE 'sata|raid|scsi|sas'
lsblk

# Per-disk SMART
sudo smartctl --scan
sudo smartctl -i /dev/sdX
sudo smartctl -H /dev/sdX
```

**Record per disk:**
| # | Device (/dev/daX) | Model | Capacity | Rotation | SMART health | Controller (B110i / PCI card) |
|---|---|---|---|---|---|---|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |
| 4 | | | | | | |
| 5 | | | | | | |
| 6 | | | | | | |

---

## 5. Controller Topology

The ML110 has both an onboard controller (B110i) and a PCI SATA controller — these
may be different controllers serving different disks.

```sh
# PCI devices — look for the SATA/RAID controllers specifically
pciconf -l -v

# FreeBSD sees each controller; find the vendor/device for:
#   - "HP Smart Array B110i" (onboard, fake-RAID)
#   - Whatever PCI SATA card you added (e.g. SIL, JMicron, Marvell, LSI)
```

On Linux this would be `lspci | grep -i sata` — note the equivalent `pciconf`
output and map each disk (`/dev/daX` from §4) to the controller it hangs off.

> **For OMV**: ZFS prefers **direct disk access** (AHCI / HBA, not RAID card).
> During the OMV install, set BIOS SATA to **AHCI** mode and disable the B110i
> RAID metadata so ZFS sees raw disks. This is the same recommendation the
> FreeNAS community gives for the ML110 G6/G7 (see [truenas.com HP ML110 G6 thread](https://www.truenas.com/community/threads/hp-ml110-g6-and-freenas.5350/)).

---

## 6. BIOS / Boot Configuration

Reboot and enter the BIOS (press `F8` or `F9` during POST on most ML110 models,
or use the iLO virtual console). Capture:

| Setting | Current value | Target for OMV |
|---|---|---|
| SATA Controller Mode | `RAID` / `AHCI` / `IDE` | `AHCI` |
| B110i Smart Array | `Enabled` / `Disabled` | `Disabled` (ZFS needs raw disks) |
| Boot Mode | `BIOS` / `UEFI` | `BIOS` (OMV 8.x ISO is BIOS-only) |
| Secure Boot | `On` / `Off` | `Off` |
| Network Boot | `PXE` enabled? | note for PXE-free install |
| LO100/iLO shared port | dedicated / shared | note the iLO IP if used |

Take a photo of the relevant BIOS screens (or at minimum a screenshot) so
you can restore settings if needed.

---

## 7. Network Configuration

```sh
# Interface names and MACs
ifconfig -a

# Current IP (if DHCP gave one)
ifconfig | grep 'inet '

# Routing
netstat -rn | grep default
```

Record:
- Primary NIC MAC → map to DHCP reservation / static IP
- iLO/LO100 management IP (if configured) — useful for remote console if SSH dies later

---

## 8. Fill the Inventory Capture Template

Once all controller/BIOS data and SMART output are captured, fill in
**`docs/ideas/nas-ml110-inventory.md`** (the template) with the actual values.
That file is the single source of truth for the OMV install plan.

---

## Decision Points Resolved by This Inventory

| Question | Resolved by | If unclear |
|---|---|---|
| Which drives to stripe/raid | §3 (current RAID layout) + §4 (disk sizes) | assume mirror pairs across same-size disks |
| ZFS vs mdadm RAID | §2 (RAM ≥4 GB?) + §4 (SMART health) | ZFS needs ≥4 GB RAM; mdadm if RAM is tight |
| Boot device for OMV | §4 (all 6 disks = data?) + §1b (bay count) | use a USB 3.0 stick (32 GB) if no spare disk |
| SATA mode | §6 (current RAID vs AHCI) | set to AHCI, disable B110i |
| Controller wiring | §5 (B110i vs PCI card topology) | AHCI for both; ZFS sees all disks |

---

## References

- [OMV 8.x — Installation prerequisites](https://docs.openmediavault.org/en/8.x/prerequisites.html)
- [OMV 8.x — Installation on Debian](https://docs.openmediavault.org/en/8.x/installation/on_debian.html)
- [OMV install via ISO](https://docs.openmediavault.org/en/8.x/installation/via_iso.html)
- [ZFS plugin / ZFS-on-Linux on OMV (omv-extras)](https://wiki.omv-extras.org/doku.php?id=omv8:omv8_plugins:zfs)
- [FreeNAS → ZFS-on-Linux import caveats (OMV forum)](https://forum.openmediavault.org/index.php?thread/7633-howto-instal-zfs-plugin-use-zfs-on-omv/)
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) — parent issue
- [Idea 03 — Homelab NAS on ML110 (OMV)](../ideas/03-nas-backup-target-ml110.md) — ML110 adaptation of the NAS concept
- [Idea 01 — Homelab NAS](01-nas-backup-target.md) — original Q956 concept (historical)
