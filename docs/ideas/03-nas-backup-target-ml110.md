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
| RAM | 8 GB DDR3L | **4 GB** (confirmed) | Q956 wins — 4 GB is fine for mdadm |
| SATA topology | 2× native SATA + M.2 | ICH9R 4-port + ICH9 2-port (onboard) + **Dell SAS 6/iR (RAID-only)** | ML110 is more complex — see controller notes below |
| Boot device | needs USB or SSD | **1.8" 20 GB drive (Option B)** — all 4× 3.5" are data | Boot device decided |

**Decision**: The ML110 is already owned and has 6 drives vs. the Q956's 2 — far
more storage headroom for a backup target. The tower footprint is acceptable for a
machine that lives near the router/switch. No purchase cost. **Proceed with ML110.**

---

## Hardware Differences From Idea 01

The Q956 idea assumed a clean USFF platform. The ML110 introduces three complexities
that idea 01's hardware did not have:

1. **Onboard Intel ICH9R SATA** ("B110i") — the "B110i" is just the ICH9R SATA with
   RAID-capable firmware, not a true separate HBA. Set to **AHCI** so mdadm sees raw disks.

2. **Dell SAS 6/iR (UCS-61, 0JW063)** — a PCIe x8 **hardware RAID controller**
   supporting SAS/SATA at up to 3 Gb/s, **RAID 0/1 only**, with no JBOD/IT mode.
   mdadm needs raw disks, so this controller is **not used**.

3. **Memory constraint** — only **4 GB** RAM. Fine for OMV + mdadm RAID1; ZFS is
   explicitly **not** being used (user decision).

These are captured in the Phase 0 inventory: [`docs/runbooks/21-ml110-nas-inventory.md`]
and the fill-in template: [`docs/ideas/nas-ml110-inventory.md`].

---

## Software Choice (unchanged from idea 01)

| Option | Verdict | Reason |
|---|---|---|
| **OMV 8.x** (Debian 13) | ✅ Selected | Free, Debian-based; mdadm RAID out of the box |
| Unraid (paid) | ⏸️ Deferred | License cost; revisit if Docker-heavy NAS is needed |
| TrueNAS SCALE | ❌ Rejected | ZFS-focused; not needed since no ZFS |
| Proxmox | ❌ Rejected | Virtualization-focused; not a storage target |

OMV is the right lightweight NAS for this role.

---

## Phase 0 — Inventory & State Audit (Prerequisite)

FreeNAS on this box is likely **not bootable** and the existing array is **regular
RAID** (not ZFS), so **Phase 0 is a hard prerequisite** before any install:

- [x] Identify ML110 generation — **G5** (from Pentium E2160 @ 1.8 GHz)
- [x] Capture disk models/sizes — 4× 3.5" (2× 500 GB, 2× 250 GB) + 2× 1.8" (2× 20 GB)
- [x] Confirm controller inventory — onboard ICH9R + ICH9 + Dell SAS 6/iR (RAID-only)
- [x] SMART health check — **all 6 original + spare 1 TB PASSED**
- [ ] Capture current controller RAID layout (RAID level, member disks) from the RAID BIOS
- [ ] Confirm FreeNAS is unbootable and no data needs preservation
- [x] Map controller topology (ICH9R vs ICH9 vs Dell SAS 6/iR)
- [ ] Document BIOS SATA mode, boot order, network MAC
- [x] Fill the template: `docs/ideas/nas-ml110-inventory.md`

> **Inspection method:** since FreeNAS likely won't boot, flash a **SystemRescue**
> (or similar live Linux) USB stick and run `lspci`, `lsblk`, `smartctl`, and
> `dmidecode` from it. Capture the RAID layout from the controller BIOS/utility
> during POST instead of from the OS.

---

## Proposed OMV Install Shape (Phase 0 resolved — no ZFS)

| Decision | Choice | Why / depends on |
|---|---|---|
| **ZFS?** | **No — mdadm RAID1** | User preference: regular RAID only |
| Boot device | **1× 1.8" 20 GB drive on ICH9 SATA #5** (Option B) | Reuses owned hardware; no USB purchase needed |
| Data pool | **mdadm RAID1**: `md0` = 2× 500 GB Hitachis; `md1` = 2× 250 GB | Redundancy for backups — all drives passed SMART |
| Small drives | 1× 1.8" 20 GB = OMV OS; 2nd 1.8" + 1 TB spare **offline** | Only 5 SATA cables available |
| Filesystem | **XFS on `md0`** (primary), **ext4 on `md1`** | XFS for backup volume; ext4 secondary |
| SATA mode | AHCI, ICH9R RAID firmware **disabled** | Raw disks to mdadm |
| PCI controller | Dell SAS 6/iR **not used** | mdadm needs raw disks; card may be removed (saves power) |
| NFS export | `/export/backups` — Longhorn backup target | ADR 02 / ADR 22 |
| SMB/CIFS | `/shared` — general backup landing | Windows/macOS client access |
| Static IP | `192.168.2.x` on homelab subnet | Match homelab network |
| Arc? | No | Storage node, not a workload host |

### Option A (alternative, rejected)

The initial plan was **OMV on a ≥32 GB USB stick** (`openmediavault-flashmemory` to limit
wear), keeping all 6 internal disks as data, and using the **5th SATA cable for the 1 TB
spare** as a single-disk XFS volume. Rejected because it requires buying a USB stick and
managing flash wear, whereas **Option B** (chosen) puts an otherwise-unused **1.8" 20 GB
drive** to work as the OS disk at zero cost. See the inventory for the full cabling table.

### RAID: why software (mdadm) over hardware (Dell SAS 6/iR)

1. **No controller dependency.** Hardware RAID binds the array to the exact controller
   model — if the SAS 6/iR dies, the data needs a compatible card. mdadm stores standard
   metadata importable on any Linux box (or a USB dock).
2. **No battery-backed write cache.** The SAS 6/iR lacks a BBWC battery, forcing a choice
   between risky write-back or slow write-through. mdadm + XFS/ext4 journals safely.
3. **Per-disk visibility.** Behind hardware RAID you lose per-drive SMART/health; with
   mdadm every disk stays a normal `/dev/sdX` visible to `smartctl` and OMV.
4. **SATA support.** The SAS 6/iR is SAS-first, 3 Gb/s, and finicky with SATA disks;
   onboard ICH9R in AHCI is native SATA.
5. **Recovery portability.** Move the mdadm pair to any machine if the G5 board dies;
   hardware RAID requires same-family card hunting.
6. **Performance non-issue.** RAID1 has no parity math, so the 2-core E2160 isn't taxed;
   the GigE NIC (~110 MB/s) is the real bottleneck.
7. **RAID level parity.** The SAS 6/iR only does RAID 0/1 — same as mdadm here.
8. **Cost & power.** Onboard SATA is free; removing the card saves ~10–15 W on a 24/7 box
   and drops aging 2009 firmware.

**Honest counterpoint:** hardware RAID offloads I/O from the CPU and survives reinstalls
more transparently — negligible here given no parity workload and a GigE bottleneck.

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
│ OMV 8.x + mdadm RAID1               │
│ Storage-only: NFS export + SMB      │
└─────────────────────────────────────┘
```

The M910q runs the workloads (k3s, OpenCode, Gitea, etc.) and pushes backups to
the ML110 NAS via NFS — exactly the "local SATA disk" fast-restore target that ADR 02
described as not-yet-procured (it will instead be this ML110 NAS).

---

## Open Questions

- [x] ML110 generation — **G5**, Pentium E2160 @ 1.8 GHz, 4 GB RAM
- [x] SMART health — **all drives PASSED** (Batches 1+2, incl. spare 1 TB)
- [x] Controllers mapped — ICH9R 4-port + ICH9 2-port (onboard) + Dell SAS 6/iR (SAS1068E)
- [x] Boot device decided — **1.8" 20 GB on ICH9 #5** (Option B)
- [ ] Current RAID layout from the SAS 6/iR controller utility (capture before unplugging)
- [ ] Which 1.8" drive becomes the OMV OS disk (Hitachi vs Fujitsu)
- [ ] Confirm FreeNAS OS is unbootable / no data to preserve

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
