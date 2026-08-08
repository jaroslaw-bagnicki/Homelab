# ML110 NAS — Hardware Inventory (Fill In)

> **Phase 0 output for issue #54.** Fill in after running all steps in
> [`docs/runbooks/21-ml110-nas-inventory.md`](docs/runbooks/21-ml110-nas-inventory.md).
> Commit this file to the worktree — it's the single source of truth for the OMV install plan.

**Status**: 🧠 Idea (Phase 0 — awaiting inventory) | **Idea**: [03 — Homelab NAS on ML110](03-nas-backup-target-ml110.md) | **Worktree**: `feat/nas-ml110-omv-setup`

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
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |
| 4 | | | | | | |
| 5 | | | | | | |
| 6 | | | | | | |

**Drive bay / connector notes**:
- 3.5" bays: ___, occupied by: ___
- 2.5" / 1.8" bays: ___, occupied by: ___
- All 6 disks are data disks? ___ (If yes, OMV needs a USB stick or spare SSD for the OS disk.)

---

## 5. Controller Topology

| PCI device (from `pciconf -l -v`) | Type | Disks served (/dev/daX) |
|---|---|---|
| _fill in_ | B110i / PCI SATA / onboard | _fill in_ |
| _fill in_ | | |

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
| Boot device for OMV | _fill in_ | e.g. "USB 32 GB" — all 6 internal disks reserved for data |
| Disk pool layout | _fill in_ | e.g. "2× mirror vdevs across the 4× 3.5"" |
| Filesystem | _fill in_ (ZFS / ext4) | e.g. ZFS — RAM budget ___ GB ≥ 4 GiB minimum |
| RAID mode | AHCI (B110i disabled) | ZFS needs raw disk access |
| OMV install method | ISO direct / Debian + pkg | BIOS boot → official ISO |
| FreeNAS data handling | Wipe / preserve | FreeNAS is being wiped per issue #54 |

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
