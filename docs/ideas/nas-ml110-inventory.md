# ML110 NAS — Hardware Inventory (Fill In)

> **Phase 0 output for issue #54.** Fill in after running all steps in
> [`docs/runbooks/21-ml110-nas-inventory.md`](docs/runbooks/21-ml110-nas-inventory.md).
> Commit this file to the worktree — it's the single source of truth for the OMV install plan.

**Status**: 🧠 Idea (Phase 0 — partial inventory captured; FreeNAS likely unbootable; RAID config must be captured from controller) | **Idea**: [03 — Homelab NAS on ML110](03-nas-backup-target-ml110.md) | **Worktree**: `feat/nas-ml110-omv-setup`

---

## 1. ML110 Generation

| Field | Value |
|---|---|
| Generation (G5/G6/G7/G10) | **G5** ✅ confirmed (DMI product string) |
| CPU model | Intel Pentium Dual E2160 @ 1.8 GHz (LGA775) |
| Logical cores | 2 (1 socket, 2 cores, 2 threads) |
| BIOS version | HP **O15** |
| BIOS release date | **2009-09-10** |
| Product string | `ProLiant ML110 G5` (board by Wistron) |
| Confirmed via | SystemRescue DMI dump (hardinfo2) |

---

## 2. System Specifications

| Field | Value |
|---|---|
| Total RAM | **4 GB** (3868 MB usable) — **2× 2 GiB DDR2-800 PC2-6400 ECC** (Samsung), slots DIMM1 + DIMM3; 2 of 4 slots free |
| ECC | **Yes — single-bit ECC** (bonus for ZFS) |
| iLO / LO100 | **LO100 present** (ServerEngines SE / IPMI modules loaded) |
| Power supply wattage | _fill in_ |
| GPU | **Matrox G200e [Pilot] ServerEngines** — server management video (LO100); explains 1024×768 cap |

---

## 3. Current RAID / Storage Configuration (before wipe)

> **Note:** FreeNAS OS is likely **not bootable**, and the existing array was **regular RAID**, not ZFS. Capture the current RAID layout from the controller BIOS/utility before wiping, so the new OMV disk layout can be planned.
>
> **⚠ Live inspection finding:** under SystemRescue only the boot USB stick is visible — **none of the 6 internal disks appear**. Likely cause: the drives hang off the SAS1068E (Dell SAS 6/iR) in RAID firmware with no volume defined. Confirm with `lsblk`; enter the SAS 6/iR BIOS during POST (`Ctrl+C`/`Ctrl+R`) to see the configured volumes.

| Controller | RAID level | Member disks | Virtual disk size | Status | Notes |
|---|---|---|---|---|---|
| _TBD_ (B110i / Dell SAS 6/iR) | _TBD_ | _TBD_ | _TBD_ | _TBD_ | |
| | | | | | |
| | | | | | |

**How to capture (pick based on what boots):**
- **Dell SAS 6/iR**: Enter the RAID BIOS (`Ctrl+C` or `Ctrl+R` during POST) and note the virtual disk(s), RAID level, and member disks.
- **HP B110i**: Enter Option ROM (`F8` during POST) and note logical drive configuration.
- If neither utility is reachable, document physical cabling and infer from drive sizes.

**Current RAID layout (verbatim from controller utility):**
```
(fill in)
```

---

## 4. Disk Inventory

| # | Device (/dev/daX) | Model | Capacity | Rotation (RPM) | SMART health | Controller |
|---|---|---|---|---|---|---|
| 1 | _TBD_ | Hitachi Travelstar HTS541020G9SA00 | 20 GB | 5400 | _TBD_ | _TBD_ |
| 2 | _TBD_ | Fujitsu MHV2020BH | 20 GB | _TBD_ | _TBD_ | _TBD_ |
| 3 | _TBD_ | Hitachi HDS721050CLA662 | 500 GB | 7200 | _TBD_ | _TBD_ |
| 4 | _TBD_ | Hitachi HDS721050CLA662 | 500 GB | 7200 | _TBD_ | _TBD_ |
| 5 | _TBD_ | Western Digital Caviar Blue WD2500AAKX | 250 GB | 7200 | _TBD_ | _TBD_ |
| 6 | _TBD_ | Western Digital RE3 / Enterprise Storage WD2502ABYS | 250 GB | 7200 | _TBD_ | _TBD_ |

**Power requirements (from labels):**
- Hitachi Travelstar 20 GB: `5V 1.0A`
- Fujitsu 20 GB: `5V 0.50A`

**Other details:**
- Hitachi 500 GB drives: HP part number `647466-001`, manufactured May 2012.
- Fujitsu 20 GB: manufacturing date July 18, 2007.
- Western Digital Caviar Blue 250 GB: manufacturing date August 24, 2012.
- Western Digital RE3 250 GB: manufacturing date February 14, 2010.

**Drive bay / connector notes**:
- 3.5" bays: 4× occupied by Hitachi 500 GB (×2), WD Caviar Blue 250 GB, WD RE3 250 GB
- 2.5" / 1.8" bays: 2× occupied by Hitachi Travelstar 20 GB, Fujitsu 20 GB
- All 6 disks are data disks? **Yes** (OMV needs a USB stick or spare SSD for the OS disk.)
- **Visibility under SystemRescue: NONE** — run `lsblk` and `smartctl --scan` to check; if the drives only appear after a SAS 6/iR volume is defined (or after cross-flashing), that's a Phase 0 blocker for the pool layout.

---

## 5. Controller Topology

Confirmed from SystemRescue `lspci`:

| PCI address | Device | Type | Ports | Role |
|---|---|---|---|---|
| `00:1f.2` | Intel 82801IR/IO/IH (ICH9R/DO/DH) | **4-port SATA controller, current mode = IDE** | 4× SATA | onboard SATA |
| `00:1f.5` | Intel 82801I (ICH9 Family) | **2-port SATA controller, current mode = IDE** | 2× SATA | onboard SATA |
| `01:00.0` | Broadcom/LSI **SAS1068E** Fusion-MPT | **Dell SAS 6/iR** hardware RAID (PCIe x8) | 2× internal SAS | RAID 0/1 controller |
| `0e:00.0` | Broadcom NetXtreme BCM5722 | Gigabit Ethernet | — | NIC (`enp14s0`) |

> Note: there is **no separate "B110i" PCI device** — the HP "B110i" is just the ICH9R SATA in RAID-capable firmware. The only true hardware RAID controller is the SAS1068E.

**Dell SAS 6/iR (SAS1068E) details:**
- Part numbers: UCS-61, 0JW063
- Bus interface: PCI-Express x8
- Supported drives: SAS and SATA (up to 3 Gb/s)
- RAID support: RAID 0, RAID 1
- Connectors: 2× internal SAS ports for drive backplanes / arrays
- Kernel driver: Fusion-MPT (`mptsas`/`mptscsih`)

**Important OMV/ZFS consideration:**
The Dell SAS 6/iR is a **hardware RAID controller**, not an HBA/JBOD controller. It only exposes RAID 0/1 virtual disks to the OS, not raw individual drives. For ZFS we prefer raw disk access (AHCI / HBA / IT-mode). Two possible paths:
1. Use the **onboard ICH9R SATA in AHCI mode** for all six drives and do not use the Dell SAS 6/iR for the data pool.
2. Cross-flash or replace the SAS 6/iR with an LSI/Avago/Broadcom HBA in IT-mode (e.g. LSI 9211-8i / cross-flash the 1068E itself) so ZFS sees raw disks.

Current assumption (pending live inspection): ICH9R set to AHCI, Dell SAS 6/iR optionally used for a separate RAID 1 pair if an HBA is not available.

---

## 6. BIOS Configuration (current vs. OMV target)

| Setting | Current | Target (OMV) |
|---|---|---|
| SATA Controller Mode | `IDE` (ICH9R + ICH9 both IDE) | `AHCI` |
| B110i / ICH9R RAID firmware | enabled (as SAS1068E volume / IDE) | `Disabled` (AHCI, raw disks) |
| Boot Mode | BIOS | `BIOS` (OMV ISO is BIOS-only) |
| Secure Boot | N/A (G5 has none) | `Off` |
| Boot device / order | USB | USB stick (PXE/RPL/BOOTP also available) |
| Network boot protocol | PXE (also RPL, BOOTP) | `Disabled` for local USB install |
| LO100/iLO shared port mode | _fill in_ | |
| RTC clock | Drifted ~13 days (26.07 → 08.08) | NTP in OMV + consider CMOS battery |

---

## 7. Network Configuration

| Interface | MAC address | Current IP | Notes |
|---|---|---|---|
| `enp14s0` (Broadcom BCM5722) | `78:e7:d1:53:fb:87` | **DHCP `192.168.2.164`** | primary NIC; gw/DNS `192.168.2.1` |
| iLO / LO100 | _fill in_ | _fill in_ | management (if present) |

**Planned OMV static IP** (on the homelab subnet `192.168.2.0/24`): `_fill in_` (e.g. reserve a `.2.x` address for the NAS; current DHCP lease is `.164`)

---

## 8. OMV Install Decisions (resolved by this inventory)

| Decision | Chosen approach | Rationale |
|---|---|---|
| Boot device for OMV | USB stick (≥32 GB) | All 6 internal disks are data disks |
| Disk pool layout | **TBD** — depends on SMART health and controller topology | Likely: ZFS mirror vdevs across the 4× 3.5" drives; 2× 1.8" drives too small (20 GB each) for meaningful data pool — leave unused |
| Filesystem | ZFS (acceptable at 4 GB; mdadm as fallback) | ZFS minimum is ~4 GB; with only 4 GB total, mirror vdevs are fine but avoid dedup/compression overhead and leave the 1.8" drives out of the pool. **ECC RAM confirmed** — good fit for ZFS |
| RAID mode | AHCI (B110i disabled) | ZFS needs raw disk access; Dell SAS 6/iR is RAID-only and not ideal for ZFS |
| OMV install method | Official ISO | BIOS boot → OMV 8.x ISO |
| FreeNAS data handling | Wipe | No ZFS pools; existing array is regular RAID; no data preservation expected |

**Resolved by SystemRescue report (hardinfo2):**
1. ✅ Generation confirmed **G5** (DMI), BIOS HP `O15` (2009-09-10).
2. ✅ CPU Pentium E2160, 2 cores @ 1.8 GHz; RAM 4 GB = 2× 2 GiB DDR2-800 **ECC**, 2 slots free.
3. ✅ Controllers mapped: ICH9R 4-port SATA (IDE), ICH9 2-port SATA (IDE), Dell SAS 6/iR (SAS1068E), BCM5722 NIC.
4. ✅ NIC `enp14s0` MAC `78:e7:d1:53:fb:87`, DHCP `192.168.2.164`, gw `192.168.2.1`.
5. ✅ LO100 present (ServerEngines SE + IPMI).
6. ⚠ **Internal disks not visible** under SystemRescue (only USB stick) — needs `lsblk` / SAS 6/iR BIOS check.

**Open questions still requiring live inspection:**
1. **Why are the 6 internal disks not visible?** — `lsblk`, `smartctl --scan`; check SAS 6/iR volumes in its BIOS.
2. SMART health of all 6 drives (some are ~15+ years old).
3. Current RAID layout from the controller utility (RAID level, member disks, virtual disk size).
4. Whether the drives can move to the ICH9R SATA in AHCI mode (cabling dependent).
5. Confirm FreeNAS OS is unbootable and no data needs preservation.
6. LO100 management IP (if configured).

---

## 9. Photos / Physical Notes

- [x] POST / system DMI — G5 confirmed via hardinfo2
- [ ] BIOS SATA/AHCI screen photo
- [ ] Drive bay / wiring photo
- [ ] FreeNAS admin UI screenshot (version string)

**Assorted notes**:
```
Display: Matrox G200e (LO100 management GPU) → capped at 1024x768; monitor HP LA2206 supports 1920x1080 but GPU/driver won't drive it. Not relevant for a storage NAS.
CPU temps: 43-46°C at idle — healthy.
RTC drifted ~13 days; NTP required once OMV is installed.
CPU microcode: no microcode update present (mds/spec_store_bypass shown vulnerable) — low risk for a storage-only node, but worth noting.
```
