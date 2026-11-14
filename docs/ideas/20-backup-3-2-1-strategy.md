# Idea 20 — 3‑2‑1 Backup Strategy for the Homelab

> Formalise the lab's backups as the classic **3‑2‑1 rule**: **3 copies** of the data, on **2 different
> media**, with **1 copy off-site**. The off-site leg is now decided — **Backblaze B2** as the cloud
> backup target ([ADR 50](../decisions/50-backblaze-b2-offsite-backup.md), superseding ADR 02's Azure Blob
> choice); the rest of the rule is mapped onto what the lab already runs: the Beetle NAS as the local
> second copy, Restic + `vzdump` as the tools.

**Status**: 🧠 Idea — 3‑2‑1 adopted by [ADR 49](../decisions/49-backup-3-2-1-strategy.md); off-site target decided by [ADR 50](../decisions/50-backblaze-b2-offsite-backup.md),
full 3‑2‑1 rollout not started.
**Date**: 2026-11-11
**Sources**: operator request 2026‑11‑11 · [ADR 02](../decisions/02-backup-strategy-restic-blob.md) ·
[research 10](../research/10-backup-strategy.md) · [research 14](../research/14-backup-cost-comparison.md) ·
Backblaze B2 pricing page (2026‑11)
**Related**: [#13](https://github.com/jaroslaw-bagnicki/Homelab/issues/13) (Restic Ansible redo — the
"Not Scheduled" row in [overview](../overview.md)) · [runbook 07](../runbooks/07-restic-backup.md) ·
[ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md) (NAS backup target) ·
[idea 17](17-truenas-vs-omv-nas-os.md) / [#187](https://github.com/jaroslaw-bagnicki/Homelab/issues/187)
(OMV→TrueNAS migration — the NAS leg changes shape if it lands) · [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)
(k3s/Longhorn backup target on the NAS) · [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164)
(FreeIPA `ipa-backup` to the NAS) · [#62](https://github.com/jaroslaw-bagnicki/Homelab/issues/62)
(Longhorn NFS backup target) · [research 41](../research/41-machine-identity-kerberos.md) (PBS/vzdump
paths to the NAS)

---

## The rule mapped to the lab

| 3‑2‑1 element | What it is here |
|---|---|
| **3 copies** | (1) live data on the node, (2) local copy on `nas` (Beetle, `md0` RAID1 1 TB), (3) off-site copy in a **Backblaze B2** bucket |
| **2 media** | local magnetic/flash storage (node SSD + NAS HDD mirror) vs cloud object storage (B2) |
| **1 off-site** | B2 bucket in an EU region (Frankfurt/Central Europe), Object Lock governance — fire/theft/ransomware-**resistant** copy; **decided by [ADR 50](../decisions/50-backblaze-b2-offsite-backup.md)** |

## What backs up what

- **Host configs & file data** (`lab` SSD, per-node `/etc`, Ansible-managed state): **Restic** → local
  repo on the NAS (SMB/NFS) + **Restic S3 backend → B2** (same repo, two remotes, or a second repo —
  TBD at implementation in [#13](https://github.com/jaroslaw-bagnicki/Homelab/issues/13)). Restic password
  stays in Azure Key Vault (ADR 06/#6 pattern); the B2 application key/secret go there too. The old
  Azure Blob repo (runbook 07) is migrated with `restic copy` and then retired — Blob is no longer a
  backup target (ADR 50).
- **Proxmox guests on `pve1`/`pve2`**: `vzdump` → NAS (NFS/SMB datastore) as copy 2; the NAS copy then
  replicated to B2 by Restic (or PBS later — research 41) as copy 3.
- **k3s/Longhorn volumes** (once #44 lands): Longhorn backup target = NFS export on `nas` (#62), then
  to B2.
- **FreeIPA** (#164 M2): `ipa-backup` artefact to the NAS. **Authentik** (#165 M6): PostgreSQL dump +
  `AUTHENTIK_SECRET_KEY` pair to the NAS.
- **Not backed up** (deliberate, #123): logs — 30‑day retention in VictoriaLogs, out of backup scope.

## Retention (carried from ADR 02)

Daily ×7, weekly ×4, monthly ×6 — applied per repo on the B2 side (Restic `--keep-*` flags). Trade-off
vs the old Azure Blob target (superseded by ADR 50): B2 pay-as-you-go has no archive/cold tier, so
long-retention monthly snapshots stay at $6.95/TB — fine at lab scale; revisit if the dataset grows
past ~1 TB.

## Open questions

- One Restic repo with two remotes (NAS + B2) vs two repos — dedupe is per-repo, so two repos double
  storage but decouple local restore from cloud; decide with #13.
- B2 bucket region: EU‑Central (Frankfurt) for GDPR/Poland proximity — confirm available region at
  bucket creation.
- Immutability: B2 Object Lock **governance mode with a 30‑day default retention** on the bucket —
  ransomware-resistant (the bucket key has no `bypassGovernance`; that stays with the offline master
  key); note `forget --prune` cannot delete locked packs before retention expires, so align the lock
  window with the Restic retention tiers (ADR 50).
- Sequencing with [#187](https://github.com/jaroslaw-bagnicki/Homelab/issues/187) (OMV→TrueNAS): the NAS
  copy survives either OS (mdadm→ZFS cutover is destructive — the B2 copy is the safety net during it,
  which is exactly what 3‑2‑1 demands).
