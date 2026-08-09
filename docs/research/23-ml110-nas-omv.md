# 23 — ML110 NAS (OMV): Hardware & Software Research

**Source**: SystemRescue 13.02 live session + hardinfo2 report + `smartctl` scans, Aug 08 2026 · Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
**Scope**: Repurposing the retired HP ProLiant ML110 G5 as the homelab NAS backup target — hardware findings, controller topology, disk health, and the RAID/boot/OS trade-offs.

---

## Decision Summary

| Decision | Outcome |
|---|---|
| Platform | HP ProLiant **ML110 G5** (already owned) — beats buying a Fujitsu Q956 |
| OS | **OpenMediaVault 8.x** (Debian 13), official ISO, BIOS boot |
| Filesystem / RAID | **No ZFS** — **mdadm RAID1** + XFS/ext4 |
| Data pool | `md0` = 2× 500 GB Hitachis (mirror), `md1` = 2× 250 GB (mirror) |
| Boot device | **1× 1.8" 20 GB drive on ICH9 SATA #5** (Option B) |
| Hardware RAID controller | **Not used** (Dell SAS 6/iR / SAS1068E) |

---

## Why the ML110 over the Q956

| Factor | Q956 (idea 01) | ML110 (this build) | Verdict |
|---|---|---|---|
| Acquisition cost | ~195 PLN (used) + new drives + caddy | **0 PLN** (already owned) | ML110 wins — no purchase |
| Form factor | USFF, ~1.9 L, near-silent | 4U tower, louder, larger | Q956 wins on footprint/noise |
| Drive count | 2× 500 GB 2.5" | **4× 3.5" + 2× 1.8"** (6 drives) + spare 1 TB | ML110 wins — more capacity/redundancy |
| CPU | i5-6500T (4C/4T) | Intel Pentium E2160 @ 1.8 GHz (2C/2T) | Q956 wins on compute |
| RAM | 8 GB DDR3L | **4 GB** (2× 2 GiB DDR2-800) | Q956 wins; 4 GB fine for mdadm |
| SATA topology | 2× native SATA + M.2 | ICH9R 4-port + ICH9 2-port + **Dell SAS 6/iR (RAID-only)** | ML110 more complex |
| Boot device | needs USB or SSD | **1.8" 20 GB drive (Option B)** | Boot device decided |

**Decision**: ML110 is owned, has 6 drives, and needs no purchase. Tower footprint is acceptable for a machine near the router/switch. **Proceed with ML110.**

---

## Hardware Findings (SystemRescue, 2026-08-08)

### System

| Field | Value |
|---|---|
| Generation | **ML110 G5** (DMI product string, board by Wistron) |
| CPU | Intel Pentium Dual E2160 @ 1.8 GHz, 2 cores (LGA775) |
| RAM | **4 GB** = 2× 2 GiB **DDR2-800 ECC** (Samsung), slots DIMM1+DIMM3, 2 free |
| ECC | **Single-bit ECC** — bonus for data integrity |
| BIOS | HP **O15**, 2009-09-10 |
| GPU | Matrox **G200e [Pilot]** (server management video / LO100) → 1024×768 cap |
| LO100 | Present (ServerEngines SE + IPMI modules loaded) |
| NIC | Broadcom BCM5722 (`enp14s0`), MAC `78:e7:d1:53:fb:87` |

### Controller topology

| PCI address | Device | Type | Role |
|---|---|---|---|
| `00:1f.2` | Intel ICH9R 82801IR | **4-port SATA, IDE mode** | onboard SATA |
| `00:1f.5` | Intel ICH9 82801I | **2-port SATA, IDE mode** | onboard SATA |
| `01:00.0` | Broadcom/LSI **SAS1068E** | **Dell SAS 6/iR** hardware RAID (PCIe x8) | RAID 0/1 only, no JBOD |
| `0e:00.0` | Broadcom BCM5722 | Gigabit Ethernet | NIC |

> Note: there is **no separate "B110i" PCI device** — "B110i" is just the ICH9R SATA with RAID-capable firmware. The only true hardware RAID controller is the SAS1068E.

### Disk inventory + SMART (all PASSED)

| # | Model (SMART) | Serial | Size | Role |
|---|---|---|---|---|
| 1 | Hitachi Travelstar HTS541020G9SA00 | `MPBFL0X9G1W9WM` | 20 GB | OMV OS (candidate) |
| 2 | Fujitsu MHW2020BH | `NZ0GT772LN18` | 20 GB | OMV OS (candidate) |
| 3 | Hitachi HDS721050CLA660 | `JP1572FL1849SK` | 500 GB | `md0` |
| 4 | Hitachi HDS721050CLA660 | `JP1572FL167V6K` | 500 GB | `md0` mirror |
| 5 | WDC WD2500AAKX-75U6AA0 | `WD-WCC2F0157761` | 250 GB | `md1` |
| 6 | GB0250EAFYK (labeled "WD RE3") | `WCAT1F035986` | 250 GB | `md1` mirror |
| 7 | WDC WD10EZEX-00BN5A0 (spare) | `WD-WCC3F7AKKXUT` | 1 TB | offline (no cable) |

**Label vs SMART discrepancies:** the 500 GB Hitachis label `CLA662` but report `CLA660` (HP OEM variant); the "WD RE3" drive actually reports as `GB0250EAFYK` (rebadged); the Fujitsu label `MHV2020BH` reports as `MHW2020BH`. **SMART identity is authoritative.**

---

## Software Choice

| Option | Verdict | Reason |
|---|---|---|
| **OMV 8.x** (Debian 13) | ✅ Selected | Free, Debian-based; mdadm RAID out of the box |
| Unraid (paid) | ⏸️ Deferred | License cost; revisit if Docker-heavy NAS is needed |
| TrueNAS SCALE | ❌ Rejected | ZFS-focused; not needed since no ZFS |
| Proxmox | ❌ Rejected | Virtualization-focused; not a storage target |

**ZFS vs mdadm:** ZFS is viable at 4 GB ECC but the user chose **regular RAID only**. mdadm RAID1 gives redundancy with zero RAM pressure and full `smartctl` visibility.

---

## RAID: why software (mdadm) over hardware (Dell SAS 6/iR)

1. **No controller dependency.** Hardware RAID binds the array to the exact controller model — if the SAS 6/iR dies, data needs a compatible card. mdadm metadata imports on any Linux box (or a USB dock).
2. **No battery-backed write cache.** The SAS 6/iR lacks BBWC, forcing risky write-back or slow write-through. mdadm + XFS/ext4 journals safely.
3. **Per-disk visibility.** Behind hardware RAID you lose per-drive SMART; with mdadm every disk stays a normal `/dev/sdX`.
4. **SATA support.** The SAS 6/iR is SAS-first, 3 Gb/s, and finicky with SATA disks; onboard ICH9R in AHCI is native SATA.
5. **Recovery portability.** Move the mdadm pair to any machine if the G5 board dies.
6. **Performance non-issue.** RAID1 has no parity math; the GigE NIC (~110 MB/s) is the bottleneck, not the 2-core CPU.
7. **RAID level parity.** The SAS 6/iR only does RAID 0/1 — same as mdadm here.
8. **Cost & power.** Onboard SATA is free; removing the card saves ~10–15 W on a 24/7 box.

**Counterpoint:** hardware RAID offloads I/O and survives reinstalls more transparently — negligible here given no parity workload and a GigE bottleneck.

---

## Boot Device: Option A vs Option B

| | Option A (rejected) | Option B (chosen) |
|---|---|---|
| OMV OS on | Dedicated ≥32 GB USB stick (`flashmemory` plugin) | **1× 1.8" 20 GB drive on ICH9 SATA #5** |
| 5th SATA cable → | **1 TB spare** (single-disk XFS) | 1.8" OMV OS disk |
| Cost | USB stick purchase + flash-wear management | Zero — reuses owned hardware |
| All 6 internal disks as data | Yes | 4× 3.5" data; one 1.8" is the OS |

**Chosen: Option B** — reuses an otherwise-unusable 1.8" drive as the OS disk, no purchase, no USB wear management. The 1 TB spare stays offline, addable later.

---

## References

- Idea [03 — Homelab NAS on ML110](docs/ideas/03-nas-backup-target-ml110.md) — the plan/implementation doc
- Inventory: [docs/ideas/nas-ml110-inventory.md](docs/ideas/nas-ml110-inventory.md) — single source of truth for hardware
- Runbook [21 — ML110 inventory](docs/runbooks/21-ml110-nas-inventory.md)
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
- [ADR 02 — Backup Strategy](docs/decisions/02-backup-strategy-restic-blob.md)
- [ADR 22 — k3s + Azure Arc](docs/decisions/22-k3s-arc-homelab.md) — NFS backup target for Longhorn
- [ADR 01 — Hardware Selection](docs/decisions/01-hardware-selection-m910q.md) — the M910q homelab server
