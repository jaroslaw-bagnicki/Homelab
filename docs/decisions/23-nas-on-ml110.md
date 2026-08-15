# NAS on the HP ProLiant ML110 (OpenMediaVault)

**Date:** 2026-08-08
**Status:** Accepted

---

## Context

The homelab needs a dedicated **backup target NAS** for the primary server (M910q, ADR 01): an NFS export for Longhorn volume snapshots (ADR 02, ADR 22) and local SMB/CIFS for general backup landing. The original idea (idea 01) scoped a new Fujitsu Esprimo Q956 (~195 PLN + drives). A retired **HP ProLiant ML110 G5** (previously a FreeNAS box, likely unbootable, disks on regular hardware RAID) was available in the home for **zero acquisition cost** — research 23 analyzed reusing it.

Constraints surfaced in the Phase 0 inventory (issue #54, runbook 21):
- **Hardware**: Pentium E2160 @ 1.8 GHz (2C/2T), **4 GB** DDR2-800 **ECC** RAM, no LO100/iLO (direct console only).
- **Controllers**: onboard ICH9R 4-port SATA (IDE mode) + ICH9 2-port SATA + Dell SAS 6/iR (SAS1068E) hardware RAID — RAID 0/1 only, no JBOD.
- **Disks**: 2× Hitachi 500 GB, 2× 250 GB (WDC WD2500AAKX + GB0250EAFYK), 2× 2.5" 20 GB cold spares, a **spare Goodram C40 120 GB SSD**, and a **spare 1 TB WD10EZEX**. All SMART-passed.
- **FreeNAS data**: no ZFS pools to preserve; existing array is regular RAID and the old controller is being removed.

The NAS is a **storage-only node** — it does not run Docker/k3s workloads. The compute/Arc host remains the M910q (ADR 22).

---

## Decision

**Repurpose the HP ProLiant ML110 G5 as the homelab NAS backup target, running OpenMediaVault 8.x (Debian 13) with mdadm software RAID1.**

### Key decisions

> Settled during Phase 0 and recorded in research 23's Decision Summary; owned by this ADR as the authoritative record.

1. **OMV 8.x** on a Debian 13 base — free, Debian-based, web UI, native mdadm management. Aligns with the original idea's software choice.
2. **No ZFS** — **mdadm RAID1 + XFS/ext4** instead. At 4 GB RAM, ZFS would work with ECC but the operator chose regular RAID only: zero RAM pressure, full per-disk `smartctl` visibility, importable on any Linux box.
3. **Boot device: Goodram C40 120 GB SSD** on ICH9 SATA #5 (Option D). Single reliable boot disk (SMART-passed), no hardware RAID in the boot path, 6× the OS capacity of the 20 GB drives. The 2× 2.5" 20 GB drives become cold spares.
4. **Data pool: mdadm RAID1** — `md0` = 2× 500 GB Hitachis (XFS), `md1` = 2× 250 GB (ext4). Both pairs are mirror vdevs with redundancy.
5. **Dell SAS 6/iR removed** — hardware RAID binds arrays to the controller, hides per-disk SMART, adds a battery-less write-cache risk, and does not support mdadm raw disks. Removing it also saves ~10–15 W on a 24/7 box.
6. **BIOS SATA = AHCI**, ICH9R RAID firmware disabled — raw disks to mdadm.
7. **Static IP `192.168.2.210`** on the homelab subnet (research 24 / runbook 23, switch port 3), replacing the DHCP lease.
8. **1 TB WD10EZEX spare unplugged** for now — its content is reviewed during OMV setup and its role (bulk volume vs offline) decided then.

---

## Consequences

- **Free and no new hardware** — the NAS costs nothing to acquire; the drives and SSD were already in hand.
- **No controller dependency** — mdadm arrays import on any Linux box (or a USB dock) if the G5 board dies; no compatible RAID-card hunting.
- **Per-disk visibility** — SMART stays readable per `/dev/sdX`; failed disks are hot-swappable into the mirror.
- **No purchase for the OS disk** — the spare SSD boot avoids sourcing a USB stick plus `flashmemory` wear management.
- **Power cost is the main negative** — the ML110 draws an estimated ~80 W idle / ~130 W load (~€150–200/yr), the most power-hungry box in the homelab (M910q idles ~8 W). Mitigations (HDD spindown, optional scheduled power) are planned but not part of the base setup.
- **4 GB RAM ceiling** — fine for mdadm + XFS/ext4; disqualifies ZFS-heavy features (dedup) and any future Docker/k3s ambitions on this node.
- **Storage-only scope** — the NAS does not join Azure Arc and does not host workloads; the M910q remains the compute/Arc surface.
- **Direct-console operations** — no LO100/iLO means BIOS changes and recovery are physical-console activities.

### Alternatives Considered

- **Buy the Fujitsu Q956 (idea 01 V1)** — ~195 PLN + new drives + caddy; ~1/4 the power cost (~€40–45/yr vs ~€150–200/yr) and near-silent. Rejected: the ML110 is already owned with 6 drive bays and needs no purchase; power economics keep the Q956 as a future power-savings move if the ML110's capacity isn't needed.
- **TrueNAS SCALE / ZFS** — ZFS-focused, elegant snapshots/checksums, viable at 4 GB ECC. Rejected: operator chose no ZFS; mdadm RAID1 gives redundancy with zero RAM pressure and simpler ops.
- **Unraid** — paid license; deferred unless a Docker-heavy NAS is ever needed.
- **Hardware RAID on the Dell SAS 6/iR** — strong controller dependency (arrays bind to the card), no battery-backed write cache, no per-disk SMART, RAID 0/1 only. Rejected (see decision 5).
- **OS on a ≥32 GB USB stick (Option A) or on the 2× 20 GB drives (Option B/C)** — USB adds flash-wear management and a purchase; the 20 GB drives give a cramped OS volume and/or a hardware-RAID boot dependency. Superseded by the spare SSD (Option D).

---

## References

- [Research 23 — ML110 NAS (OMV)](../research/23-ml110-nas-omv.md) — hardware/software trade-off analysis
- [Idea 03 — Homelab NAS on ML110](../ideas/03-nas-backup-target-ml110.md)
- [Runbook 21 — ML110 inventory](../runbooks/21-ml110-nas-inventory.md)
- [Runbook 22 — ML110 OMV setup](../runbooks/22-ml110-omv-setup.md)
- [Research 24 — network topology design](../research/24-network-topology-design.md) — static IP `192.168.2.210`
- [ADR 01 — Hardware Selection](01-hardware-selection-m910q.md) — the M910q homelab server
- [ADR 02 — Backup Strategy](02-backup-strategy-restic-blob.md) — Restic to local SATA + Azure Blob
- [ADR 22 — k3s + Azure Arc](22-k3s-arc-homelab.md) — Longhorn NFS backup target on the NAS
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) — NAS setup on the ML110
