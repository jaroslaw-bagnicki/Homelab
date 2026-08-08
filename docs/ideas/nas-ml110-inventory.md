# ML110 NAS — Hardware Inventory (Fill In)

> **Phase 0 output for issue #54.** Fill in after running all steps in
> [`docs/runbooks/21-ml110-nas-inventory.md`](docs/runbooks/21-ml110-nas-inventory.md).
> Commit this file to the worktree — it's the single source of truth for the OMV install plan.

**Status**: 🧠 Idea (Phase 0 — partial inventory captured; runbook still needs live execution) | **Idea**: [03 — Homelab NAS on ML110](03-nas-backup-target-ml110.md) | **Worktree**: `feat/nas-ml110-omv-setup`

---

## 1. ML110 Generation

| Field | Value |
|---|---|
| Generation (G5/G6/G7/G10) | _fill in_ |
| CPU model (`sysctl hw.model`) | _fill in_ |
| Logical cores (`sysctl hw.ncpu`) | _fill in_ |
| BIOS version (`sysctl smbios.bios.version`) | _fill in_ |
| BIOS release date (`sysctl smbios.bios.release`) | _fill in_ |
| Product string (`sysctl smbios.system.product`) | _fill in_ |
| Confirmed via physical POST / iLO: | _fill in_ |

---

## 2. System Specifications

| Field | Value |
|---|---|
| Total RAM (`sysctl hw.physmem` in GB) | _fill in_ |
| iLO / LO100 generation | _fill in_ (none / iLO 3 / iLO 5 / etc.) |
| Power supply wattage | _fill in_ |

---

## 3. ZFS Pool Audit (FreeNAS state — captured before wipe)

| Pool name | Vdev layout | Feature flags | Encryption | Status | Notes |
|---|---|---|---|---|---|
| _fill in_ | e.g. `raidz2-0: ad0,ad1,ad2,ad3` | `feature@...` | yes/no (GELI?) | ONLINE/DEGRADED | |
| _fill in_ | | | | | |
| _fill in_ | | | | | |

**`zpool status -v` output:**
```
(fill in — paste verbatim)
```

**`zpool get all` key feature flags per pool:**
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

---

## 5. Controller Topology

| PCI device | Type | Disks served (/dev/daX) |
|---|---|---|
| Onboard HP Smart Array B110i | SATA/AHCI controller / fake-RAID (onboard) | _TBD_ |
| Dell SAS 6/iR (UCS-61, 0JW063) | Hardware RAID controller (PCI-Express x8) | _TBD_ |

**Dell SAS 6/iR controller details:**
- Part numbers: UCS-61, 0JW063
- Bus interface: PCI-Express x8
- Supported drives: SAS and SATA (up to 3 Gb/s)
- RAID support: RAID 0, RAID 1
- Connectors: 2× internal SAS ports for drive backplanes / arrays

**Important OMV/ZFS consideration:**
The Dell SAS 6/iR is a **hardware RAID controller**, not an HBA/JBOD controller. It only exposes RAID 0/1 virtual disks to the OS, not raw individual drives. For ZFS we prefer raw disk access (AHCI / HBA / IT-mode). Two possible paths:
1. Use the **onboard B110i in AHCI mode** for all six drives and do not use the Dell SAS 6/iR for the data pool.
2. Cross-flash or replace the SAS 6/iR with an LSI/Avago/Broadcom HBA in IT-mode (e.g. LSI 9211-8i) so ZFS sees raw disks.

Current assumption (pending live inspection): B110i set to AHCI, Dell SAS 6/iR optionally used for a separate RAID 1 pair if an HBA is not available.

---

## 6. BIOS Configuration (current vs. OMV target)

| Setting | Current | Target (OMV) |
|---|---|---|
| SATA Controller Mode | _fill in_ | `AHCI` |
| B110i Smart Array | _fill in_ | `Disabled` |
| Boot Mode | _fill in_ | `BIOS` (OMV ISO is BIOS-only) |
| Secure Boot | _fill in_ | `Off` |
| Boot device / order | _fill in_ | (USB stick or spare SSD) |
| LO100/iLO shared port mode | _fill in_ | |

---

## 7. Network Configuration

| Interface | MAC address | Current IP | Notes |
|---|---|---|---|
| _fill in_ (e.g. `bxe0`, `em0`) | _fill in_ | _fill in_ | primary NIC |
| iLO / LO100 | _fill in_ | _fill in_ | management (if present) |

**Planned OMV static IP** (on the homelab subnet `192.168.2.0/24`): `_fill in_`

---

## 8. OMV Install Decisions (resolved by this inventory)

| Decision | Chosen approach | Rationale |
|---|---|---|
| Boot device for OMV | USB stick (≥32 GB) | All 6 internal disks are data disks |
| Disk pool layout | **TBD** — depends on SMART health and controller topology | Likely: ZFS mirror vdevs across the 4× 3.5" drives; 2× 1.8" drives too small (20 GB each) for meaningful data pool — consider log/cache SLOG or leave unused |
| Filesystem | ZFS (preferred) | Modern ZFS plugin on OMV 8.x; mirror vdevs give redundancy with good space efficiency |
| RAID mode | AHCI (B110i disabled) | ZFS needs raw disk access; Dell SAS 6/iR is RAID-only and not ideal for ZFS |
| OMV install method | Official ISO | BIOS boot → OMV 8.x ISO |
| FreeNAS data handling | Wipe | FreeNAS is being wiped per issue #54 |

**Open questions still requiring live inspection:**
1. Exact ML110 generation, CPU, RAM.
2. SMART health of all 6 drives (some are ~15+ years old).
3. Whether all drives are visible on the B110i in AHCI mode, or if some are cabled to the Dell SAS 6/iR.
4. FreeNAS ZFS pool layout before wipe.

---

## 9. Photos / Physical Notes

- [ ] POST screen photo (confirms generation)
- [ ] BIOS SATA/AHCI screen photo
- [ ] Drive bay / wiring photo
- [ ] FreeNAS admin UI screenshot (version string)

**Assorted notes**:
```
(fill in)
```
