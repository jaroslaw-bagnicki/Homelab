# Idea 03 — Homelab NAS on HP ProLiant ML110 (OpenMediaVault)

> **V2 of idea 01** (`01-nas-backup-target.md`). The original idea scoped a brand-new
> Fujitsu Esprimo Q956 bought second-hand. This version adapts that concept to
> the **already-owned HP ProLiant ML110** that previously ran FreeNAS. FreeNAS is
> wiped; this is a fresh OpenMediaVault install.
>
> Idea 01 (`< 01-nas-backup-target.md`) is left **unchanged** as the historical
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
| CPU | i5-6500T (4C/4T) | Xeon / i3 class (gen-dependent) | Comparable |
| RAM | 8 GB DDR3L | TBD (likely 4–8 GB; max depends on gen) | Inventory needed |
| SATA topology | 2× native SATA + M.2 | B110i "fake RAID" + **PCI SATA card** + onboard SATA | ML110 is more complex — Phase 0 inventory required |
| Boot device | needs USB or SSD | needs USB/SSD — all 6 internal drives are data | Both need a boot device |

**Decision**: The ML110 is already owned and has 6 drives vs. the Q956's 2 — far
more storage headroom for a backup target. The tower footprint is acceptable for a
machine that lives near the router/switch. No purchase cost. **Proceed with ML110.**

---

## Hardware Differences From Idea 01

The Q956 idea assumed a clean USFF platform. The ML110 introduces two complexities
that idea 01's hardware did not have:

1. **HP B110i "fake RAID" controller** — firmware-assisted RAID, not true HBA.
   ZFS (and OMV's mdadm) want raw disk access in **AHCI mode**. BIOS must disable
   B110i RAID and set SATA to AHCI. (This is standard practice for ZFS on the ML110
   G6/G7 per the [TrueNAS ML110 G6 thread](https://www.truenas.com/community/threads/hp-ml110-g6-and-freenas.5350/).)

2. **PCI SATA controller** — a third-party add-in card that may carry some of the
   6 drives. Controller topology (which disks on B110i vs PCI card) must be mapped
   in Phase 0 so we know each disk's path under Linux.

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

Since the ML110 was running FreeNAS and "wasn't used for a very long time," and
since we can't recall exact disk capacities or controller wiring, **Phase 0 is a
hard prerequisite** before any install:

- [ ] Identify ML110 generation (G5/G6/G7/G10) — determines BIOS layout, max RAM
- [ ] Capture FreeNAS ZFS pool layout, feature flags, encryption status (even though wiping — informs new pool design)
- [ ] SMART health check on all 6 drives — a long-idle machine may have degraded disks
- [ ] Map controller topology (B110i vs PCI SATA card vs onboard) — which `/dev/sdX` hangs where
- [ ] Document BIOS SATA mode, boot order, network MAC
- [ ] Fill the template: `docs/ideas/nas-ml110-inventory.md`

> **Why an inventory template?** Because the machine has been dormant and disk
> capacities are unknown, a fill-in form prevents guesswork during the OMV install.
> It also creates a permanent record so a future rebuild (or repo handoff) doesn't
> require re-probing dormant hardware. If you'd rather fold it into the runbook
> itself, that's a one-step change.

---

## Proposed OMV Install Shape (pending Phase 0)

| Decision | Tentative choice | Why / depends on |
|---|---|---|
| Boot device | USB 3.0 stick (32 GB) | All 6 internal drives reserved for data — see inventory |
| Data pool | ZFS mirror vdevs across 4× 3.5" | Redundancy for backups — depends on drive sizes/SMART |
| Small drives | 2× 1.8" as ZFS log/cache or separate pool | Depends on capacity |
| Filesystem | ZFS (via openmediavault-zfs plugin) | Data integrity; needs ≥4 GB RAM |
| SATA mode | AHCI, B110i RAID **disabled** | Direct disk access for ZFS |
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
│ ML110  (this idea)                  │
│ OMV 8.x + ZFS                       │
│ Storage-only: NFS export + SMB      │
└─────────────────────────────────────┘
```

The M910q runs the workloads (k3s, OpenCode, Gitea, etc.) and pushes backups to
the ML110 NAS via NFS — exactly the "local SATA disk" fast-restore target that ADR 02
described as not-yet-procured (it will instead be this ML110 NAS).

---

## Open Questions

- [ ] ML110 exact generation (G5/G6/G7/G10) → Phase 0
- [ ] Drive sizes & SMART health → Phase 0
- [ ] PCI SATA card model & chipset → Phase 0 (Linux driver support)
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