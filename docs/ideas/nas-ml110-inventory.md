# ML110 NAS — Hardware Inventory (Fill In)

> **Phase 0 output for issue #54.** Fill in after running all steps in
> [`docs/runbooks/21-ml110-nas-inventory.md`](docs/runbooks/21-ml110-nas-inventory.md).
> Commit this file to the worktree — it's the single source of truth for the OMV install plan.

**Status**: 🧠 Idea (Phase 0 — inventory complete; **no ZFS — mdadm RAID1 + OMV on 1.8" OS disk** decided; RAID layout capture from SAS 6/iR still pending) | **Idea**: [03 — Homelab NAS on ML110](03-nas-backup-target-ml110.md) | **Worktree**: `feat/nas-ml110-omv-setup`

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
| ECC | **Yes — single-bit ECC** (bonus for data integrity) |
| iLO / LO100 | **LO100 present** (ServerEngines SE / IPMI modules loaded) |
| Power supply wattage | _fill in_ |
| GPU | **Matrox G200e [Pilot] ServerEngines** — server management video (LO100); explains 1024×768 cap |

---

## 3. Current RAID / Storage Configuration (before wipe)

> **Note:** FreeNAS OS is likely **not bootable**, and the existing array was **regular RAID**, not ZFS. Capture the current RAID layout from the controller BIOS/utility before wiping, so the new OMV disk layout can be planned.

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

| # | Device (/dev/sdX) | Model (SMART) | Serial | Capacity | Rotation (RPM) | SMART health | Controller |
|---|---|---|---|---|---|---|---|
| 1 | `/dev/sda` | Hitachi Travelstar HTS541020G9SA00 | `MPBFL0X9G1W9WM` | 20 GB | 5400 | ✅ **PASSED** | onboard |
| 2 | `/dev/sdb` | Fujitsu **MHW2020BH** | `NZ0GT772LN18` | 20 GB | _TBD_ | ✅ **PASSED** | onboard |
| 3 | `/dev/sda` | Hitachi HDS721050CLA660 | `JP1572FL1849SK` | 500 GB | 7200 | ✅ **PASSED** | onboard ICH9R |
| 4 | `/dev/sdb` | Hitachi HDS721050CLA660 | `JP1572FL167V6K` | 500 GB | 7200 | ✅ **PASSED** | onboard ICH9R |
| 5 | `/dev/sdc` | WDC WD2500AAKX-75U6AA0 | `WD-WCC2F0157761` | 250 GB | 7200 | ✅ **PASSED** | onboard ICH9R |
| 6 | `/dev/sdd` | **GB0250EAFYK** | `WCAT1F035986` | 250 GB | 7200 | ✅ **PASSED** | onboard ICH9R |
| 7 | `/dev/sdc` (Batch 2) | **WDC WD10EZEX-00BN5A0** (spare) | `WD-WCC3F7AKKXUT` | **1.0 TB** | 7200 | ✅ **PASSED** | onboard |

**Power requirements (from labels):**
- Hitachi Travelstar 20 GB: `5V 1.0A`
- Fujitsu 20 GB: `5V 0.50A`

**Other details:**
- Hitachi 500 GB drives: HP part number `647466-001`, manufactured May 2012.
- Fujitsu 20 GB: manufacturing date July 18, 2007.
- Western Digital Caviar Blue 250 GB: manufacturing date August 24, 2012.
- Western Digital RE3 250 GB: manufacturing date February 14, 2010.

> **Note on device names:** `/dev/sdX` names are **transient** — they depend on which SATA port each drive is plugged into during a given scan batch. The **serial number is the stable identifier** for building the array. Batch 1 = 4× 3.5" drives; Batch 2 = 2× 1.8" drives + spare 1 TB.

**⚠ Label vs SMART discrepancies (2026-08-08):**
- The two 500 GB Hitachis label as `HDS721050CLA662` but SMART reports **`HDS721050CLA660`** — the `662` is the HP OEM variant number (P/N `647466-001`); same drive family. Go by SMART model.
- The drive labeled **WD RE3 WD2502ABYS** actually reports as **`GB0250EAFYK`** (serial `WCAT1F035986`) — this is likely a relabeled/HP-rebadged drive, **not** the WD RE3 stated on the label. Treat the SMART identity as authoritative.
- The Fujitsu 20 GB labels as `MHV2020BH` but SMART reports **`MHW2020BH`** — close family; go by SMART.
- **Spare drive discovered**: `WDC WD10EZEX-00BN5A0` 1 TB (serial `WD-WCC3F7AKKXUT`) — not part of the original 6-drive count.

**Drive bay / connector notes**:
- 3.5" bays: 4× occupied by Hitachi 500 GB (×2), WD Caviar Blue 250 GB, "WD RE3" (= GB0250EAFYK) 250 GB
- 2.5" / 1.8" bays: 2× occupied by Hitachi Travelstar 20 GB, Fujitsu 20 GB
- **+1 spare 3.5"**: WDC WD10EZEX 1 TB (not originally mounted)
- All 6 mounted disks are data disks? **Yes** — OMV OS goes on **one of the 1.8" 20 GB drives** (Option B)
- **Final cabling plan (5 SATA cables):**
  - ICH9R ports #1–#4 → the 4× 3.5" data drives (mdadm RAID1 pairs)
  - ICH9 port #5 → one 1.8" 20 GB drive as the OMV system disk
  - Second 1.8" 20 GB + 1 TB spare → left disconnected (offline)
- **Visibility resolved** — the earlier "no disks" was because they were physically detached. Attached on the onboard ICH9R SATA ports, drives enumerate fine as `/dev/sdX` in IDE mode. No SAS 6/iR involvement needed for scanning.

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

**Decision (no ZFS):** mdadm needs raw disks, so the Dell SAS 6/iR is **not used**. The onboard ICH9R SATA set to **AHCI** provides the raw disks. The SAS 6/iR may be left seated but disconnected, or physically removed to save ~10–15 W.

---

## 6. BIOS Configuration (current vs. OMV target)

| Setting | Current | Target (OMV) |
|---|---|---|
| SATA Controller Mode | `IDE` (ICH9R + ICH9 both IDE) | `AHCI` (for mdadm; keeps raw disks visible) |
| B110i / ICH9R RAID firmware | enabled (as SAS1068E volume / IDE) | `Disabled` (raw disks to mdadm) |
| Boot Mode | BIOS | `BIOS` (OMV ISO is BIOS-only) |
| Secure Boot | N/A (G5 has none) | `Off` |
| Boot device / order | USB | 1.8" 20 GB OMV disk (ICH9 #5) |
| Network boot protocol | PXE (also RPL, BOOTP) | `Disabled` for local install |
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
| **ZFS?** | **No — mdadm RAID1 instead** | User preference: regular RAID only, no ZFS for now |
| Boot device for OMV | **1× 1.8" 20 GB drive on ICH9 SATA port #5** (Option B) | Reuses owned hardware; no USB stick purchase. Use the Hitachi Travelstar or Fujitsu 20 GB as the OS disk |
| Disk pool layout | **mdadm RAID1**: `md0` = 2× 500 GB Hitachis (500 GB usable); `md1` = 2× 250 GB (250 GB usable) | Software RAID1 pairs for redundancy; 1 TB spare and 1.8" spare left out (no cable) |
| Filesystem | **XFS on `md0`** (primary), **ext4 on `md1`** | XFS for backup target volume; ext4 for secondary/bulk |
| RAID mode | **mdadm software RAID** on onboard ICH9R SATA, set to **AHCI** in BIOS | No hardware RAID dependency; Dell SAS 6/iR unused (or physically removed) |
| OMV install method | Official ISO | BIOS boot → OMV 8.x ISO |
| FreeNAS data handling | Wipe | No ZFS pools; existing array is regular RAID; no data preservation expected |
| 1 TB spare (WD10EZEX) | **Offline for now** (no free SATA cable) | Can be added later when a cable/port is freed |

**Resolved by SystemRescue report (hardinfo2) + Batches 1 & 2 SMART:**
1. ✅ Generation confirmed **G5** (DMI), BIOS HP `O15` (2009-09-10).
2. ✅ CPU Pentium E2160, 2 cores @ 1.8 GHz; RAM 4 GB = 2× 2 GiB DDR2-800 **ECC**, 2 slots free.
3. ✅ Controllers mapped: ICH9R 4-port SATA (IDE), ICH9 2-port SATA (IDE), Dell SAS 6/iR (SAS1068E), BCM5722 NIC.
4. ✅ NIC `enp14s0` MAC `78:e7:d1:53:fb:87`, DHCP `192.168.2.164`, gw `192.168.2.1`.
5. ✅ LO100 present (ServerEngines SE + IPMI).
6. ✅ **All drives PASSED SMART health** (2026-08-08, Batches 1+2) — 4× 3.5" + 2× 1.8" + spare 1 TB, serials recorded above.
7. ✅ Disk visibility resolved — the drives were simply detached; they enumerate fine on the onboard ICH9R SATA.
8. ⚠ **Label mismatch**: the "WD RE3" drive actually reports as `GB0250EAFYK`; Fujitsu label `MHV2020BH` reports as `MHW2020BH`.
9. ✅ **Spare 1 TB WD10EZEX** discovered and healthy.
10. ✅ **Layout decision made**: no ZFS → mdadm RAID1; OMV OS on 1.8" 20 GB (Option B).

**Open questions still requiring live inspection:**
1. Current RAID layout from the SAS 6/iR controller utility (RAID level, member disks, virtual disk size) — capture before unplugging it.
2. Confirm FreeNAS OS is unbootable and no data needs preservation.
3. LO100 management IP (if configured).
4. Which 1.8" drive becomes the OMV OS disk (Hitachi vs Fujitsu).
5. Whether to physically remove the Dell SAS 6/iR (saves ~10–15 W) or leave seated but disconnected.

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
RTC: drifts and reverts to ~23-26 July after reboot; RTC correction is not persisted to hwclock. NTP required once OMV is installed; consider replacing the CR2032 CMOS battery.
CPU microcode: no microcode update present (mds/spec_store_bypass shown vulnerable) — low risk for a storage-only node, but worth noting.
SMART (2026-08-08): Batches 1+2 — all 6 original drives + spare 1 TB PASSED. All healthy; no drive excluded so far.
```
