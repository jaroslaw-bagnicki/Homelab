# Idea 03 — Homelab NAS on HP ProLiant ML110 (OpenMediaVault)

> **V2 of idea 01** (`01-nas-backup-target.md`). The original idea scoped a brand-new
> Fujitsu Esprimo Q956 bought second-hand. This version adapts that concept to
> the **already-owned HP ProLiant ML110** that previously ran FreeNAS. FreeNAS is
> wiped; this is a fresh OpenMediaVault install.
>
> The full hardware/software trade-off analysis lives in
> [**Research 23 — ML110 NAS (OMV)**](../research/23-ml110-nas-omv.md);
> this doc is the implementation plan.

**Status**: 🔨 Implementing — SMB `/shared` backup share live (2026-08-22, [runbook 26](../runbooks/26-ml110-nas-exports.md)); NFS `/export/backups` + Longhorn pending  
**Date**: 2026-08-08  
**Idea**: 01 — [Homelab NAS](01-nas-backup-target.md) (historical V1)  
**Research**: [23 — ML110 NAS (OMV)](../research/23-ml110-nas-omv.md)  
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
| Boot device | **Goodram C40 120 GB SSD on ICH9 SATA #5** (Option D — confirmed) |
| Data pool | **mdadm RAID1**: `md0` = 2× 500 GB Hitachis; `md1` = 2× 250 GB |
| Bulk volume | **1 TB WD10EZEX — unplugged for now**; content review during OMV setup, role TBD |
| Filesystem | **XFS on `md0`** (primary), **ext4 on `md1`** |
| SATA mode | **AHCI**, ICH9R RAID firmware disabled |
| Dell SAS 6/iR | **Not used** (mdadm needs raw disks); may be removed to save power |
| NFS export | `/export/backups` — Longhorn backup target |
| SMB/CIFS | `/shared` — general backup landing |
| Static IP | `192.168.2.210` on homelab subnet |
| Arc? | No — storage node, not a workload host |

---

## Phase 0 — Inventory & State Audit (Prerequisite)

Runbook: [`22-ml110-nas-inventory.md`](../runbooks/22-ml110-nas-inventory.md)

- [x] Identify ML110 generation — **G5** (DMI)
- [x] Capture disk models/sizes + SMART health — **all drives PASSED** (incl. spare 1 TB)
- [x] Confirm controller inventory — ICH9R 4-port + ICH9 2-port + Dell SAS 6/iR
- [x] Map controller topology — see research 23 / inventory
- [x] Decide layout — no ZFS, mdadm RAID1, SSD boot (Option D)
- [x] **Goodram C40 SSD health check** — **PASSED** (Option D confirmed)
- [x] SAS 6/iR RAID layout — **not captured** (controller removed; old FreeNAS array not preserved)
- [ ] Confirm FreeNAS is unbootable / no data to preserve
- [x] Consolidate findings into [research 23](../research/23-ml110-nas-omv.md) — remaining TBD: PSU wattage, 1 TB content

---

## Next Steps (implementation)

1. Flash OMV 8.x ISO to a boot USB (reuse YUMI) and install to the **Goodram 120 GB SSD**.
2. BIOS: SATA → AHCI, ICH9R RAID disabled, boot from the SSD.
3. `mdadm` RAID1 pairs → `md0` (2× 500 GB) + `md1` (2× 250 GB); XFS/ext4.
4. Review the 1 TB WD10EZEX content (plug in during OMV setup), then decide its role (bulk volume vs offline).
5. NFS `/export/backups` + SMB `/shared`; static IP `192.168.2.210`.
6. Verify NFS from the M910q (`showmount -e`); point Longhorn at it.
7. Repo: runbook 23 (`docs/runbooks/23-ml110-omv-setup.md`) + idea → ADR 23.

---

## Lifecycle

📋 **Planned** → 🔨 **Implementing** once Phase 0 completes and the OMV install
begins → ✅ **Done** when the NAS is online and the Longhorn backup target is
verified. Then graduates to an **ADR** (e.g. ADR 23 — NAS on ML110).

---

## References

- [Research 23 — ML110 NAS (OMV)](../research/23-ml110-nas-omv.md) — hardware/software trade-off analysis
- [Idea 01 — Homelab NAS](01-nas-backup-target.md) — original Q956 scoping (V1, unchanged)
- [Runbook 22 — ML110 inventory](../runbooks/22-ml110-nas-inventory.md)
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
- [ADR 02 — Backup Strategy](../decisions/02-backup-strategy-restic-blob.md)
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — NFS backup target for Longhorn
- [ADR 01 — Hardware Selection](../decisions/01-hardware-selection-m910q.md) — the M910q homelab server
