# Backup Strategy — the 3‑2‑1 Rule for the Homelab

**Date:** 2026-11-11  
**Status:** Accepted  
**Companion:** [ADR 50](50-backblaze-b2-offsite-backup.md) (the off-site vendor choice, which
supersedes ADR 02's Azure Blob target)

---

## Context

[ADR 02](02-backup-strategy-restic-blob.md) (2026‑05) set Restic → Azure Blob as the off-site leg when
the lab was a single M910q with no local backup target — the cloud copy was effectively the *only*
second copy. Since then the lab grew a real local target: the **Beetle M‑III NAS** with `md0` RAID1,
1 TB usable ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)), plus `vzdump` for the `pve1`/`pve2`
guests, Longhorn-to-NFS planned for k3s (#199/#62), `ipa-backup` (#164) and Authentik dumps (#165) to
the NAS. What does not exist anywhere is a stated **rule** — nothing says how many copies must exist
or where they may live, and ADR 02 still reads *In Progress* while the restic redo sits dormant
([#13](https://github.com/jaroslaw-bagnicki/Homelab/issues/13), "Not Scheduled" in
[overview](../overview.md)).

The operator asked to formalise the backup posture as the classic **3‑2‑1 rule**
([idea 20](../ideas/20-backup-3-2-1-strategy.md)).

## Decision

Adopt the **3‑2‑1 rule** as the lab's backup policy:

| Element | Rule | Mapped to the lab |
|---|---|---|
| **3 copies** | live data + 2 backups | (1) live on the node, (2) local copy on `nas` (Beetle `md0` RAID1), (3) off-site copy in cloud object storage |
| **2 media** | backups on 2 different media types | local disk (node SSD / NAS HDD mirror) vs cloud object storage |
| **1 off-site** | one copy immune to site loss (fire/theft/ransomware) | one cloud bucket, EU region, Object Lock enabled — vendor per [ADR 50](50-backblaze-b2-offsite-backup.md) |

Tooling and retention are unchanged from ADR 02: **Restic** (encrypted, deduplicated) for host/file
data with daily ×7 / weekly ×4 / monthly ×6; **`vzdump`** → NAS for Proxmox guests, the NAS copy then
replicated to the off-site bucket as copy 3; Longhorn → NFS on `nas` for k3s volumes once #199 lands;
`ipa-backup` and the Authentik dump pair land on the NAS. Logs stay out of backup scope by design
(#123 — 30‑day VictoriaLogs retention).

Scope guard: 3‑2‑1 covers **data**; it does not cover full bare-metal images of every node (those
remain per-runbook, e.g. runbook 27 Rescuezilla images to the NAS).

## Consequences

- Every new workload must declare its three copies at onboarding (NAS share + bucket prefix), instead
  of inheriting "whatever runbook 07 did" — the rule becomes the checklist item in reviews.
- The off-site leg is a single vendor (ADR 50) with **one bucket-scoped application key per backup
  stream** (`homelab-restic`, `homelab-vzdump`, …) plus one Restic password per repo, all in Azure
  Key Vault — the credential surface grows with streams, not with nodes.
- Restore drills become meaningful: copy 2 (NAS) for fast local restore, copy 3 (cloud) for site loss —
  the DR runbook must rehearse both paths, not just the cloud one.
- Cost is bounded: copy 3 at ~100–300 GB deduplicated is ~$0.70–2.10/month on B2 (ADR 50).
- Trade-off accepted: one off-site copy, not two clouds — if the off-site vendor has a bad day, recovery
  depends on it; mitigated by Object Lock + Restic's self-contained repo format (recovery needs only
  the binary + password) and by the NAS copy surviving any cloud incident.
- Sequencing note: during the destructive mdadm→ZFS cutover of #187 (OMV→TrueNAS), the off-site copy
  is the safety net — which is exactly what 3‑2‑1 demands.

### Alternatives Considered

- **Keep ADR 02's implicit posture (cloud = the only backup)** — rejected: with the NAS now existing,
  a single cloud copy violates 3‑2‑1 and makes every restore dependent on internet egress.
- **3‑3‑1 (two off-site clouds)** — rejected for now at lab scale (doubles cost and credential surface);
  revisit above ~1 TB dataset (see ADR 50 alternatives).
- **2‑1‑0 (local mirror only)** — rejected: no fire/theft/ransomware protection; this was the rejected
  "local-only" alternative in ADR 02 already.
