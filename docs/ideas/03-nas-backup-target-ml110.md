# Idea 03 — Homelab NAS on HP ProLiant ML110 (OpenMediaVault)

> **V2 of idea 01** (`01-nas-backup-target.md`). The original idea scoped a brand-new
> Fujitsu Esprimo Q956 bought second-hand. This version adapts that concept to
> the **already-owned HP ProLiant ML110** that previously ran FreeNAS. FreeNAS is
> wiped; this is a fresh OpenMediaVault install.
>
> Idea 01 (`01-nas-backup-target.md`) is left **unchanged** as the historical
> Q956 scoping doc.

**Status**: 📋 Planned
**Date**: 2026-08-08
**Sources**:
- [Gemini thread 1](https://share.gemini.google/IT4sMLWoypH6) — hardware selection, Unraid vs OMV, disk/RAM config
- [Gemini thread 2](https://share.gemini.google/9EUcOTYIaaDo) — USFF/SFF form factor exploration
- OMV 8.x installation docs: https://docs.openmediavault.org/en/8.x/installation/
- Issue [#54 — Set up Homelab NAS on ML110](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)

---

## Topic

Repurpose the retired **HP ProLiant ML110** (previously a FreeNAS box, currently
powered off and unused for a long time) as the Homelab's dedicated **backup target
NAS**. Install OpenMediaVault 8.x fresh (FreeNAS/TrueNAS config is discarded — no
pool import needed), configure the drives into a redundant data pool, and expose
NFS + SMB shares. Primary consumer: the Longhorn/k3s backup target on the M910q
homelab server (ADR 02, ADR 22).

---

## Why repurpose the ML110 instead of buying the Q956?

| Factor | Q956 (idea 01) | ML110 (this doc) | Verdict |
|---|---|---|---|
| Acquisition cost | ~195 PLN (used) + new drives + caddy | **0 PLN** (already owned) | ML110 wins — no purchase needed |
| Form factor | USFF, ~1.9 L, near-silent | 4U tower, louder, larger | Q956 wins on footprint/noise |
| Drive count | 2× 500 GB 2.5" | **4× 3.5" + 2× 1.8"** (6 drives) | ML110 wins — more capacity/redundancy |
| CPU | i5-6500T (4C/4T) | Intel Pentium E2160 @ 1.8 GHz (2C/2T, ML110 **G5**) | Q956 wins on compute |
| RAM | 8 GB DDR3L | **4 GB** (confirmed) | Q956 wins — 4 GB is borderline for ZFS |
| SATA topology | 2× native SATA + M.2 | B110i "fake RAID" + **Dell SAS 6/iR (RAID-only)** + onboard SATA | ML110 is more complex — see controller notes below |
| Boot device | needs USB or SSD | needs USB/SSD — all 6 internal drives are data | Both need a boot device |

**Decision**: The ML110 is already owned and has 6 drives vs. the Q956's 2 — far
more storage headroom for a backup target. The tower footprint is acceptable for a
machine that lives near the router/switch. No purchase cost. **Proceed with ML110.**

---

## Hardware Differences From Idea 01

The Q956 idea assumed a clean USFF platform. The ML110 introduces three complexities
that idea 01's hardware did not have:

1. **HP B110i "fake RAID" controller** — firmware-assisted RAID, not true HBA.
   ZFS (and OMV's mdadm) want raw disk access in **AHCI mode**. BIOS must disable
   B110i RAID and set SATA to AHCI.

2. **Dell SAS 6/iR (UCS-61, 0JW063)** — a PCIe x8 **hardware RAID controller**
   supporting SAS/SATA at up to 3 Gb/s, **RAID 0/1 only**, with no JBOD/IT mode.
   It exposes only virtual disks to the OS, so ZFS cannot see raw drives through it.
   Likely left unused for the ZFS pool unless it is cross-flashed or replaced with an
   IT-mode HBA (e.g. LSI 9211-8i).

3. **Memory constraint** — only **4 GB** RAM. ZFS works at 4 GB but is borderline;
   mdadm RAID1 + ext4/XFS is the fallback if ZFS feels constrained.

These are captured in the Phase 0 inventory: [`docs/runbooks/21-ml110-nas-inventory.md`]
and the fill-in template: [`docs/ideas/nas-ml110-inventory.md`].

---

## Software Choice (unchanged from idea 01)

| Option | Verdict | Reason |
|---|---|---|
| **OMV 8.x** (Debian 13) | ✅ Selected | Free, Debian-based, ZFS plugin via omv-extras |
| Unraid (paid) | ⏸️ Deferred | License cost; revisit if Docker-heavy NAS is needed |
| TrueNAS SCALE | ❌ Rejected | Needs 8 GB+ RAM minimum, matched disks; overkill for a backup target |
| Proxmox | ❌ Rejected | Virtualization-focused; not a storage target |

Same decision as idea 01 — OMV is the right lightweight NAS for this role.

---

## Phase 0 — Inventory & State Audit (Prerequisite)

FreeNAS on this box is likely **not bootable** and the existing array is **regular
RAID** (not ZFS), so **Phase 0 is a hard prerequisite** before any install:

- [x] Identify ML110 generation — **G5** (from Pentium E2160 @ 1.8 GHz)
- [x] Capture disk models/sizes — 4× 3.5" (2× 500 GB, 2× 250 GB) + 2× 1.8" (2× 20 GB)
- [x] Confirm controller inventory — onboard B110i + Dell SAS 6/iR (RAID-only)
- [ ] Capture current controller RAID layout (RAID level, member disks) from the RAID BIOS
- [ ] SMART health check on all 6 drives — a long-idle machine may have degraded disks
- [ ] Confirm FreeNAS is unbootable and no data needs preservation
- [ ] Map controller topology (B110i vs Dell SAS 6/iR) — which `/dev/sdX` hangs where
- [ ] Document BIOS SATA mode, boot order, network MAC
- [ ] Fill the template: `docs/ideas/nas-ml110-inventory.md`

> **Why an inventory template?** Because the machine has been dormant and disk
> capacities are unknown, a fill-in form prevents guesswork during the OMV install.
> It also creates a permanent record so a future rebuild (or repo handoff) doesn't
> require re-probing dormant hardware. If you'd rather fold it into the runbook
> itself, that's a one-step change.
>
> **Inspection method:** since FreeNAS likely won't boot, flash a **SystemRescue**
> (or similar live Linux) USB stick and run `lspci`, `lsblk`, `smartctl`, and
> `dmidecode` from it. Capture the RAID layout from the controller BIOS/utility
> during POST instead of from the OS.

---

## Proposed OMV Install Shape (pending Phase 0)

| Decision | Tentative choice | Why / depends on |
|---|---|---|
| Boot device | USB stick (≥32 GB) | All 6 internal drives reserved for data — see inventory |
| Data pool | ZFS mirror vdevs across 4× 3.5" | Redundancy for backups — depends on SMART health |
| Small drives | 2× 1.8" (20 GB each) **left out** of the pool | Too small for a meaningful data pool; ZFS log/cache not worth it at 4 GB RAM |
| Filesystem | ZFS, with **mdadm + ext4/XFS as fallback** | ZFS works at 4 GB but is borderline; fall back if sluggish |
| SATA mode | AHCI, B110i RAID **disabled** | Direct disk access for ZFS |
| PCI controller | Dell SAS 6/iR **not used** for the ZFS pool | RAID-only (no JBOD/IT mode); cross-flash or swap to LSI HBA if needed |
| NFS export | `/export/backups` — Longhorn backup target | ADR 02 / ADR 22 |
| SMB/CIFS | `/shared` — general backup landing | Windows/macOS client access |
| Static IP | `192.168.2.x` on homelab subnet | Match homelab network |
| Arc? | No | Storage node, not a workload host |

---

## Relationship to the Existing Homelab

This ML110 NAS is a **sibling** to the M910q homelab server, not a replacement:

```
┌─────────────────────────────────────┐
│ M910q Tiny  (existing)              │
│ Ubuntu 24.04 → k3s + Arc            │
│ Docker workloads, AI agents         │
└──────────────┬──────────────────────┘
               │ NFS/SMB (backup target)
               ▼
┌─────────────────────────────────────┐
│ ML110 G5  (this idea)               │
│ OMV 8.x + ZFS (or mdadm)            │
│ Storage-only: NFS export + SMB      │
└─────────────────────────────────────┘
```

The M910q runs the workloads (k3s, OpenCode, Gitea, etc.) and pushes backups to
the ML110 NAS via NFS — exactly the "local SATA disk" fast-restore target that ADR 02
described as not-yet-procured (it will instead be this ML110 NAS).

---

## Open Questions

- [x] ML110 generation — **G5**, Pentium E2160 @ 1.8 GHz, 4 GB RAM
- [ ] SMART health of all 6 drives → Phase 0
- [ ] Which disks hang off B110i vs Dell SAS 6/iR → Phase 0
- [ ] Current RAID layout from the controller utility → Phase 0
- [ ] Available spare USB stick or SSD for OMV boot → Phase 0

---

## Lifecycle

This idea moves from 🧠 **Idea** → 📋 **Planned** now that the ML110 is confirmed
as the platform. It will advance to 🔨 **Implementing** once Phase 0 inventory is
complete and the disk layout is decided, then close to ✅ **Done** when the OMV NAS
is online and the Longhorn backup target is verified.

At that point it graduates to an **ADR** (e.g. ADR 23 — NAS on ML110) recording the
final hardware/software decisions, and the runbook (`docs/runbooks/22-ml110-omv-setup.md`)
captures the install steps.

---

## References

- Idea [01 — Homelab NAS](01-nas-backup-target.md) — original Q956 scoping (V1, unchanged)
- Runbook [21 — ML110 inventory](docs/runbooks/21-ml110-nas-inventory.md)
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
- [ADR 02 — Backup Strategy](docs/decisions/02-backup-strategy-restic-blob.md)
- [ADR 22 — k3s + Azure Arc](docs/decisions/22-k3s-arc-homelab.md) — NFS backup target for Longhorn
- [ADR 01 — Hardware Selection](docs/decisions/01-hardware-selection-m910q.md) — the M910q homelab server
