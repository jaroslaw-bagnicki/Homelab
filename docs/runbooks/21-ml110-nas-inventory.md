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

- **Direct console** — attach a keyboard + mouse + monitor to the ML110. **There is no LO100/iLO on this box**: the LO100 expansion-card slot is empty and the management RJ45 port is fused with a metal plate, so no out-of-band management is available.
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

- Power on and watch the **POST screen** — the model (e.g. `ProLiant ML110 G5`)
  appears at the top.
- This G5 has **no LO100** (expansion-card slot empty, RJ45 fused) — no iLO/LO100 address to capture.
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
fine for OMV + mdadm** — but a memory smoke test is still worthwhile before a 24/7
NAS role. Run it before deciding the pool layout.

1. From the SystemRescue boot menu, select **Memtest86+** (not the default entry).
2. Let it run **at least one full pass** (~30–60 min on 4 GB; a first-pass smoke
   test is acceptable for now).
3. Record the result: `PASS` / `FAIL` and the number of passes/errors.

| Memtest86+ result | Implication |
|---|---|
| PASS (≥1 full pass) | RAM OK — proceed with mdadm |
| FAIL / any errors | Fix/replace the faulty module first; bad RAM risks data integrity |

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
lsblk -f

# Per-disk SMART
sudo smartctl --scan
sudo smartctl -i /dev/sdX
sudo smartctl -H /dev/sdX
```

### Batch scan procedure (only 4 SATA cables available)

This box has **4 regular SATA cables** plus the Dell SAS 6/iR SAS cable. The SAS 6/iR
cannot be used for SMART scanning (RAID firmware hides raw disks), so at most **4 disks
can be attached at once** on the onboard ICH9R SATA ports. Scan in batches:

1. **Batch 1 — the 4× 3.5" data drives** (the important ones): 2× Hitachi 500 GB,
   WD Caviar Blue 250 GB, WD RE3 250 GB → attach to the 4× onboard ICH9R SATA ports.
2. Run the SMART loop below and **record the serial of every disk** — the two 500 GB
   Hitachi drives share a model, so only the serial distinguishes them. Correlate each
   `/dev/sdX` to the physical label before unplugging.
3. **Batch 2 — the 2× 1.8" drives** (20 GB each, informational only): swap them in and
   repeat.

```sh
# SMART health per attached disk — record model + serial + health
for d in /dev/sd[a-z]; do
    echo "=== $d ==="
    smartctl -i "$d" 2>/dev/null | grep -E 'Device Model|Serial Number|User Capacity|Rotation'
    smartctl -H "$d" 2>/dev/null | grep -E 'result'
done
```

### Troubleshooting: no /dev/sdX visible

`/dev/sdX` only appears for drives the kernel sees. If nothing shows under `lsblk`:

1. Confirm at least one disk is physically attached to an **onboard SATA port** AND has
   **power** connected. (All 6 internal disks are currently detached.)
2. The SystemRescue boot stick itself is exposed as `/dev/mapper/ventoy`, **not** as a
   plain `/dev/sdX` — so the USB stick alone will not create `/dev/sd*` entries.
3. Check enumeration:
   ```sh
   lsblk
   fdisk -l
   ls /dev/sd* /dev/hd* 2>/dev/null
   dmesg | grep -iE 'sd|ata|sas|usb' | tail -40
   ```
4. If a disk is attached but still invisible: it may be cabled to the **SAS 6/iR**
   (hidden by RAID firmware) — move it to an onboard SATA port. Verify cabling with
   `lspci` (ICH9R at `00:1f.2` = onboard SATA).

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

> **For OMV (no ZFS)**: mdadm wants **direct disk access** (AHCI / HBA, not RAID card).
> During the OMV install, set BIOS SATA to **AHCI** mode and disable the B110i
> RAID metadata so mdadm sees raw disks.

---

## 6. BIOS / Boot Configuration

Reboot and enter the BIOS (press `F8` or `F9` during POST on most ML110 models).
Note: this G5 has **no iLO/LO100** — a physical keyboard + monitor is the console.
Capture:

| Setting | Current value | Target for OMV |
|---|---|---|
| SATA Controller Mode | `RAID` / `AHCI` / `IDE` | `AHCI` |
| B110i Smart Array | `Enabled` / `Disabled` | `Disabled` (mdadm needs raw disks) |
| Boot Mode | `BIOS` / `UEFI` | `BIOS` (OMV 8.x ISO is BIOS-only) |
| Secure Boot | `On` / `Off` | `Off` |
| Network Boot | `PXE` enabled? | note for PXE-free install |
| LO100/iLO shared port | N/A — LO100 not installed | — |

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
- No LO100/iLO on this G5 — no management IP to capture; rely on direct console

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
- [Idea 01 — Homelab NAS](../ideas/01-nas-backup-target.md) — original Q956 concept (historical)
