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
| Boot device | **Goodram C40 120 GB SSD on ICH9 SATA #5** (Option D — confirmed) |
| Bulk volume | **1 TB WD10EZEX — single-disk XFS** on ICH9 SATA #6 |
| Hardware RAID controller | **Not used** (Dell SAS 6/iR / SAS1068E) — may be removed to save power |

---

## Why the ML110 over the Q956

| Factor | Q956 (idea 01) | ML110 (this build) | Verdict |
|---|---|---|---|
| Acquisition cost | ~195 PLN (used) + new drives + caddy | **0 PLN** (already owned) | ML110 wins — no purchase |
| Form factor | USFF, ~1.9 L, near-silent | 4U tower, louder, larger | Q956 wins on footprint/noise |
| Drive count | 2× 500 GB 2.5" | **4× 3.5" + 2× 2.5" 20 GB + 120 GB SSD + spare 1 TB** | ML110 wins — more capacity/redundancy |
| CPU | i5-6500T (4C/4T) | Intel Pentium E2160 @ 1.8 GHz (2C/2T) | Q956 wins on compute |
| RAM | 8 GB DDR3L | **4 GB** (2× 2 GiB DDR2-800) | Q956 wins; 4 GB fine for mdadm |
| SATA topology | 2× native SATA + M.2 | ICH9R 4-port + ICH9 2-port + **Dell SAS 6/iR (RAID-only)** | ML110 more complex |
| Boot device | needs USB or SSD | **Goodram 120 GB SSD (Option D)** — 6× capacity of the 20 GB drives | Boot device decided |

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
| GPU | Matrox **G200e [Pilot]** (ServerEngines onboard console video) → 1024×768 cap |
| LO100 / IPMI | **Not available** — LO100 expansion-card slot is **empty** and the management RJ45 port is **fused with a metal plate**. No out-of-band remote management (no iLO/LO100 IPMI). |
| Remote access | **None** — direct console only: keyboard + mouse + monitor on the ML110 |
| NIC | Broadcom BCM5722 (`enp14s0`), MAC `78:e7:d1:53:fb:87` |

### Controller topology

| PCI address | Device | Type | Role |
|---|---|---|---|
| `00:1f.2` | Intel ICH9R 82801IR | **4-port SATA, IDE mode** | onboard SATA |
| `00:1f.5` | Intel ICH9 82801I | **2-port SATA, IDE mode** | onboard SATA |
| `01:00.0` | Broadcom/LSI **SAS1068E** | **Dell SAS 6/iR** hardware RAID (PCIe x8) | RAID 0/1 only, no JBOD |
| `0e:00.0` | Broadcom BCM5722 | Gigabit Ethernet | NIC |

> Note: there is **no separate "B110i" PCI device** — "B110i" is just the ICH9R SATA with RAID-capable firmware. The only true hardware RAID controller is the SAS1068E.

### Disk inventory + SMART (all PASSED unless noted)

| # | Model (SMART) | Serial | Size | Role |
|---|---|---|---|---|
| 1 | Hitachi Travelstar HTS541020G9SA00 (2.5") | `MPBFL0X9G1W9WM` | 20 GB | cold spare |
| 2 | Fujitsu MHW2020BH (2.5") | `NZ0GT772LN18` | 20 GB | cold spare |
| 3 | Hitachi HDS721050CLA660 | `JP1572FL1849SK` | 500 GB | `md0` |
| 4 | Hitachi HDS721050CLA660 | `JP1572FL167V6K` | 500 GB | `md0` mirror |
| 5 | WDC WD2500AAKX-75U6AA0 | `WD-WCC2F0157761` | 250 GB | `md1` |
| 6 | GB0250EAFYK (labeled "WD RE3") | `WCAT1F035986` | 250 GB | `md1` mirror |
| 7 | **Goodram C40 120 GB** (SSD) | `1C9C074614D500572350` | 120 GB | **OMV OS (Option D, confirmed — SMART PASSED)** |
| 8 | WDC WD10EZEX-00BN5A0 (spare) | `WD-WCC3F7AKKXUT` | 1 TB | **XFS bulk volume** |

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

## Boot Device: Option A vs Option B vs Option D

| | Option A (rejected) | Option B (superseded) | **Option D (chosen)** |
|---|---|---|---|
| OMV OS on | Dedicated ≥32 GB USB stick (`flashmemory` plugin) | 1× 2.5" 20 GB drive (ICH9 #5) | **Goodram C40 120 GB SSD (ICH9 #5)** |
| 1 TB spare | single-disk XFS on ICH9 #5 | offline | **single-disk XFS on ICH9 #6** |
| Cost | USB purchase + flash-wear mgmt | zero (reuse 2.5" drive) | zero (spare SSD found) |
| Hardware RAID needed | no | no | **no** — SAS 6/iR not used |

**Chosen: Option D** — a spare **Goodram C40 120 GB SSD** appeared, giving a single reliable boot disk with 6× the OS capacity of the 20 GB drives, no hardware RAID anywhere, and freeing both 2.5" 20 GB drives as cold spares. The 1 TB spare joins the build as a single-disk XFS bulk volume. **SSD health confirmed (SMART PASSED).**

---

## References

- Idea [03 — Homelab NAS on ML110](../ideas/03-nas-backup-target-ml110.md) — the plan/implementation doc
- Inventory: [nas-ml110-inventory.md](../ideas/nas-ml110-inventory.md) — single source of truth for hardware
- Runbook [21 — ML110 inventory](../runbooks/21-ml110-nas-inventory.md)
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
- [ADR 02 — Backup Strategy](../decisions/02-backup-strategy-restic-blob.md)
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — NFS backup target for Longhorn
- [ADR 01 — Hardware Selection](../decisions/01-hardware-selection-m910q.md) — the M910q homelab server
