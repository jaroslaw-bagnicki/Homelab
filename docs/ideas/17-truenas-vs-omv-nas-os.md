# Idea 17 — TrueNAS as the NAS OS (vs OMV)

> The Beetle NAS runs **OMV 8.5.9-1** on mdadm RAID1 + XFS and works. The operator wants to know what it
> would take — and what it would be worth — to run **TrueNAS** there instead: not because OMV is broken, but
> because this is a playground and an **enterprise-grade NAS appliance** is a different thing to learn from
> than a casual WebUI around Debian's storage stack.

**Status**: 🧠 Idea — no decision taken, nothing installed
**Date**: 2026-11-07
**Sources**: operator request, 2026-11-07 ("Homelab is my playground — experience TrueNAS as an enterprise-grade
NAS solution compared to OMV, which seems casual for less tech-oriented hobbyists") ·
[ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md) (the OS decision this would supersede) ·
[research 44](../research/44-omv-identity-integration.md) (where OMV's user model stops) ·
[TrueNAS hardware guide](https://www.truenas.com/docs/scale/25.10/gettingstarted/scalehardwareguide/) (RAM floor, 25.10 on Debian 13)
**Related**: [ADR 23](../decisions/23-nas-on-ml110.md) (the original "no ZFS, thin RAM" reasoning) ·
[research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md) (the unit's actual hardware) ·
[runbook 32](../runbooks/32-beetle-m3-omv-setup.md) / [runbook 38](../runbooks/38-nas-disk-replacement.md) (what OMV lifecycle work exists) ·
[ADR 02](../decisions/02-backup-strategy-restic-blob.md) (restic — the other integrity layer) ·
[ADR 34](../decisions/34-lan-tls-only.md) (NFSv4 `krb5p` / encrypted SMB requirement) ·
[ADR 27](../decisions/27-monitoring-strategy.md) / [ADR 36](../decisions/36-log-collector-fluentbit.md) / [ADR 10](../decisions/10-ansible-host-config.md) (the uniform fleet automation the appliance would break) ·
[ADR 43](../decisions/43-freeipa-domain-realm.md) / [ADR 44](../decisions/44-authentik-identity-provider.md) (the identity stack OMV cannot fully join)

---

## Context

The `nas` role in this lab is deliberately narrow: a **storage-only backup target** — NFS for Longhorn volume
snapshots, SMB as a restic/backup landing zone ([ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md)).
It does no compute, and it should not: the box is a **Pentium G4400 (2C/2T) with 8 GB DDR4** (one free SODIMM
slot, 32 GB max), a SanDisk 128 GB boot SSD, and **2× Seagate ST1000VT001 1 TB 2.5"** in `md0` → XFS.

The important framing: **this idea is not a bug report.** The driver is *experience*, so the success
criterion is not "is TrueNAS better?" — it is "what does the lab gain in skill, and what does it lose in
automation and stability?" Answering "better" is not required for this idea to succeed.

## What "enterprise-grade" actually means here

OMV is not a weak storage engine: it is mdadm + LVM + XFS/ext4 + Samba + NFS on Debian — the same components
enterprise Linux servers use. What feels casual is the **packaging and audience**: a community plugin-based
WebUI aimed at home users, with no commercial support path. TrueNAS is a **product**: an opinionated,
curated appliance with a vendor support path in its commercial edition, a defined hardware list, and a
lifecycle you do not assemble yourself.

So the genuinely different things to learn are:

- **ZFS** as a storage model — datasets, checksums, scrub, snapshots, `send`/`recv` replication, ARC sizing.
- **Appliance operations** — a NAS managed as a product, with its own update cadence and upgrade risk.
- **NAS semantics as a product** — share/dataset ACLs, iSCSI targets, replication tasks, cloud-sync jobs
  modelled in one UI rather than assembled from roles.

Notably, both are **Debian 13** underneath today (OMV 8.5 and TrueNAS 25.10), so the difference is the
appliance contract, not the OS family.

## What TrueNAS would actually gain

| Gain | Weight for this box |
|---|---|
| **Checksums + scrub + self-heal** on the mirror | ✅ Real — but only the *silent* corruption class. The monthly mdadm scrub already caught a failing member (`WDEPBVR3`, 2026-10-11), so failure *detection* is not the gap |
| **Snapshots on the Longhorn NFS path** | ✅ **Strongest single argument** — raw volume images have no other integrity or rollback layer; restic blobs already self-verify with `restic check --read-data` |
| **Replication (`send`/`recv`)** | ✅ Enables a real second copy later — into `pve2`'s future `zfspool`, or a USB target elsewhere |
| **NFSv4 `krb5p` + encrypted SMB out of the box** | ✅ [ADR 34](../decisions/34-lan-tls-only.md) compliance becomes a toggle, not a plugin hunt |
| **LDAP/AD join and keytab SMB auth** | ✅ Closes exactly the "OMV user database" wall found in [research 44](../research/44-omv-identity-integration.md) — relevant to [ADR 43](../decisions/43-freeipa-domain-realm.md) |
| **SMART / alerting / reporting UI** | ⚠️ Nicer, not additive — Netdata already covers the fleet |
| **Apps (Docker) and VMs (Incus)** | ❌ Irrelevant here — 2C/2T / 8 GB, and `pve1`/`pve2` are the compute hosts. Do not run apps on the NAS |

## What it would cost

- **The appliance tax — the decisive cost.** Every automation in this repo assumes a writable root, `apt` and
  systemd: `fleetadm` provisioning ([ADR 10](../decisions/10-ansible-host-config.md)), the Netdata child
  ([ADR 27](../decisions/27-monitoring-strategy.md)), Fluent Bit log shipping
  ([ADR 36](../decisions/36-log-collector-fluentbit.md)). An appliance that replaces system files on update
  turns each of those into a **per-OS exception**. That is the *exact* argument
  [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md) used to reject Unraid — swapping vendors does
  not remove it. (NUT is the exception that survives: TrueNAS ships a native UPS service, so
  [ADR 39](../decisions/39-nut-host-native.md) is unaffected.)
- **Hardware sits at the floor.** 8 GB is TrueNAS's documented minimum (up to eight drives); **16 GB is the
  practical target**. The free slot makes that ~€20, so it is a cost, not a blocker. The G4400 is fine for a
  pure file server and would not be if anything else landed on it.
- **Resilver on this media is not a selling point.** The last mdadm resync took **six days**
  (2026-10-11 → 17, [runbook 38](../runbooks/38-nas-disk-replacement.md)); a ZFS resilver is *more*
  random-access intensive, so "ZFS heals a degraded mirror faster" is not true on 2× 2.5″ drives. No ECC
  either way, so that comparison is a wash.
- **No in-place conversion.** mdadm + XFS cannot become a ZFS pool. The array is destroyed and restored from
  [ADR 02](../decisions/02-backup-strategy-restic-blob.md) backups or staged elsewhere first — which also
  means the *restore path gets exercised*, a genuine side benefit.
- **Documentation churn.** Supersedes ADR 29, rewrites [runbook 32](../runbooks/32-beetle-m3-omv-setup.md) and
  [runbook 38](../runbooks/38-nas-disk-replacement.md), plus the Caddy `omv.internal` site, state docs and
  role exclusions.

## Options

| Option | What it is | Verdict |
|---|---|---|
| **A. Trial TrueNAS on spare hardware or a VM** | Boot TrueNAS on a spare SSD/2.5″ disk (the board has **5 SATA ports** — boot SSD + 2 data leaves spares), or in a VM on `pve2`, and build a throwaway pool. OMV untouched, `md0` untouched | ⭐ **Do this first.** It buys the entire learning objective for near-zero risk, and it is the only path that answers "do I actually enjoy operating this appliance?" |
| **B. ZFS under the existing management** | OMV's `openmediavault-zfs` plugin, or plain Debian 13 + `zfs-dkms` + Samba/NFS managed by Ansible | ⭐ **Best value if the goal is ZFS.** Keeps [ADR 10](../decisions/10-ansible-host-config.md)/[27](../decisions/27-monitoring-strategy.md)/[36](../decisions/36-log-collector-fluentbit.md) intact, gains checksums/scrub/snapshots/replication — no appliance divergence |
| **C. Full TrueNAS cutover on the Beetle** | The actual proposal: wipe, install TrueNAS, create a ZFS mirror, re-point NFS/SMB, carve the NAS out of uniform automation | Acceptable **only** after A proves the appliance is wanted, and with the 16 GB upgrade |
| **D. Stay on OMV, tighten it** | Add a restic `check --read-data` schedule, keep the monthly scrub, verify SMART alerting reaches Netdata | Always on the table — nothing is broken today |

A and B are not mutually exclusive with C; the natural sequence is **A → (B or C)**.

## Open questions

- **What is the actual goal** — ZFS fluency, appliance operating experience, or "a NAS that looks like what a
  company would buy"? The first two point at B/A; the third is an argument about résumé and feel, not fit.
- **Would the lab rather have ZFS on `pve2`** (where [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md)
  already wants a `zfspool`) than on the NAS? ZFS replication between them then becomes a second backup copy.
- **Is any spare 2.5″ SSD/HDD available** for a non-destructive TrueNAS trial on the Beetle's free SATA ports?
- **If cutover happens, what is the restore rehearsal** — from Azure Blob (slow) or from a staged copy on
  `lab`? How long is the NAS's NFS export offline for Longhorn?
- **Does the appliance tax get accepted explicitly**, or does the NAS keep a documented "not Ansible-managed"
  exception in [ADR 27](../decisions/27-monitoring-strategy.md)/[36](../decisions/36-log-collector-fluentbit.md)?
  A silent exception is the one outcome to avoid.
- **Would 16 GB actually change the decision**, or is it a rationalisation of a choice already made?

## Risks worth naming

- **Re-platforming the backup target to learn a filesystem.** The backup target is the one box that must stay
  boring. If the real goal is ZFS practice, exercising ZFS elsewhere is cheaper and safer.
- **Appliance upgrades are whole-system events.** A failed TrueNAS upgrade takes the backup target with it;
  OMV's `apt` upgrades are incremental and interruptible.
- **Half-migrated automation.** Netdata child, Fluent Bit and `fleetadm` either work or are removed — a role
  that "sort of runs" against an appliance is worse than an explicit exclusion.
- **Two NAS truths in the docs** if OMV and ZFS paths are both documented without one superseding the other.

## References

- [ADR 29 — NAS backup target, Beetle M-III (OpenMediaVault)](../decisions/29-nas-backup-target-beetle-m3-omv.md) — the decision this would supersede, including the "no ZFS" reasoning inherited from ADR 23
- [ADR 23 — NAS on the HP ProLiant ML110](../decisions/23-nas-on-ml110.md) — origin of the RAM-ceiling argument (4 GB DDR2, no longer the constraint)
- [Research 32 — Beetle M-III hardware diagnostic](../research/32-wincor-beetle-m3-hardware-diagnostic.md) — CPU, RAM slots, 5 SATA ports, drive serials
- [Research 44 — OMV identity integration](../research/44-omv-identity-integration.md) — the OMV user-model wall TrueNAS' directory integration would remove
- [ADR 34 — LAN TLS only](../decisions/34-lan-tls-only.md) — the NFSv4 `krb5p` / encrypted SMB requirement
- Upstream: [TrueNAS hardware guide](https://www.truenas.com/docs/scale/25.10/gettingstarted/scalehardwareguide/) · [OpenZFS docs](https://openzfs.github.io/openzfs-docs/) · [OMV ZFS plugin](https://docs.openmediavault.org/en/stable/administration/storage/zfs.html)
