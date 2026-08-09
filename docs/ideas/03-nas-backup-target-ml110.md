# Idea 03 — Homelab NAS on HP ProLiant ML110 (OpenMediaVault)

> **V2 of idea 01** (`01-nas-backup-target.md`). The original idea scoped a brand-new
> Fujitsu Esprimo Q956 bought second-hand. This version adapts that concept to
> the **already-owned HP ProLiant ML110** that previously ran FreeNAS. FreeNAS is
> wiped; this is a fresh OpenMediaVault install.
>
> The full hardware/software trade-off analysis lives in
> [**Research 23 — ML110 NAS (OMV)**](../research/23-ml110-nas-omv.md);
> this doc is the implementation plan.

**Status**: 📋 Planned  
**Date**: 2026-08-08  
**Idea**: 01 — [Homelab NAS](01-nas-backup-target.md) (historical V1)  
**Research**: [23 — ML110 NAS (OMV)](../research/23-ml110-nas-omv.md)  
**Inventory**: [nas-ml110-inventory.md](nas-ml110-inventory.md) (single source of truth for hardware)  
**Issue**: [#54 — Set up Homelab NAS on ML110](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)

---

## Plan

Repurpose the retired **HP ProLiant ML110 G5** (previously a FreeNAS box) as the
Homelab's dedicated **backup target NAS** on OMV 8.x. No ZFS — **mdadm RAID1**.
Storage-only node; primary consumer is the Longhorn/k3s backup target on the M910q
(ADR 02, ADR 22).

| Decision | Choice |
|---|---|
| **ZFS?** | No — **mdadm RAID1** |
| Boot device | **1× 1.8" 20 GB drive on ICH9 SATA #5** (Option B) |
| Data pool | **mdadm RAID1**: `md0` = 2× 500 GB Hitachis; `md1` = 2× 250 GB |
| Filesystem | **XFS on `md0`** (primary), **ext4 on `md1`** |
| SATA mode | **AHCI**, ICH9R RAID firmware disabled |
| Dell SAS 6/iR | **Not used** (mdadm needs raw disks); may be removed to save power |
| NFS export | `/export/backups` — Longhorn backup target |
| SMB/CIFS | `/shared` — general backup landing |
| Static IP | `192.168.2.x` on homelab subnet |
| Arc? | No — storage node, not a workload host |

---

## Phase 0 — Inventory & State Audit (Prerequisite)

Runbook: [`21-ml110-nas-inventory.md`](../runbooks/21-ml110-nas-inventory.md)

- [x] Identify ML110 generation — **G5** (DMI)
- [x] Capture disk models/sizes + SMART health — **all drives PASSED** (incl. spare 1 TB)
- [x] Confirm controller inventory — ICH9R 4-port + ICH9 2-port + Dell SAS 6/iR
- [x] Map controller topology — see research 23 / inventory
- [x] Decide layout — no ZFS, mdadm RAID1, boot on 1.8" drive
- [ ] Capture current SAS 6/iR RAID layout (before unplugging it)
- [ ] Confirm FreeNAS is unbootable / no data to preserve
- [ ] Pick which 1.8" drive is the OMV OS disk (Hitachi vs Fujitsu)
- [ ] Fill the inventory template: `nas-ml110-inventory.md`

---

## Next Steps (implementation)

1. Flash OMV 8.x ISO to a boot USB (reuse YUMI) and install to the chosen 1.8" drive.
2. BIOS: SATA → AHCI, ICH9R RAID disabled, boot from the 1.8" disk.
3. `mdadm` RAID1 pairs → `md0` (2× 500 GB) + `md1` (2× 250 GB); XFS/ext4.
4. NFS `/export/backups` + SMB `/shared`; static IP `192.168.2.x`.
5. Verify NFS from the M910q (`showmount -e`); point Longhorn at it.
6. Repo: runbook 22 (`docs/runbooks/22-ml110-omv-setup.md`) + idea → ADR 23.

---

## Lifecycle

📋 **Planned** → 🔨 **Implementing** once Phase 0 completes and the OMV install
begins → ✅ **Done** when the NAS is online and the Longhorn backup target is
verified. Then graduates to an **ADR** (e.g. ADR 23 — NAS on ML110).

---

## References

- [Research 23 — ML110 NAS (OMV)](../research/23-ml110-nas-omv.md) — hardware/software trade-off analysis
- [Idea 01 — Homelab NAS](01-nas-backup-target.md) — original Q956 scoping (V1, unchanged)
- [Runbook 21 — ML110 inventory](../runbooks/21-ml110-nas-inventory.md)
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
- [ADR 02 — Backup Strategy](../decisions/02-backup-strategy-restic-blob.md)
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — NFS backup target for Longhorn
- [ADR 01 — Hardware Selection](../decisions/01-hardware-selection-m910q.md) — the M910q homelab server
