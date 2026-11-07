# Idea 17 — TrueNAS as the NAS OS (vs OMV)

> The Beetle NAS runs **OMV 8.5.9-1** on mdadm RAID1 + XFS and works. The operator wants to know what it
> would take — and what it would be worth — to run **TrueNAS** there instead: not because OMV is broken, but
> because this is a playground and an **enterprise-grade NAS appliance** is a different thing to learn from
> than a casual WebUI around Debian's storage stack.

**Status**: 🧠 Idea — **leaning to a full TrueNAS cutover on the Beetle** (option C), with the ML110 kept on
OMV as a cold standby. No decision taken, nothing installed.
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

**The predecessor box stays — as a cold standby, not a bench.** The **HP ProLiant ML110 G5** (`omv`, `.210`
today) is not being scrapped: it keeps its OMV 8.3 install, its `md0` (2× 500 GB) and `md1` (2× 250 GB)
arrays, and its 1 TB WD10EZEX offline spare, and stays **powered off** as an **ad-hoc / emergency NAS** — the box to boot
when the Beetle is being rebuilt, when a restore wants a second live SMB/NFS endpoint, or when a cutover goes
wrong badly enough to want a night's sleep. It is therefore **neither a TrueNAS trial bench nor scratch**:
nothing on it is wiped for an experiment. Its limits are why it is standby only — 4 GB DDR2 (8 GB ceiling, two
free DIMM slots), a Pentium E2160 at 1.8 GHz with **no AES-NI**, no out-of-band management, 3 fans at ~80 W.

**One chore comes with retention.** [ADR 31](../decisions/31-static-address-scheme.md) only tolerated `.210`
as "occupied until the ML110 retires" — and `.210` is also the planned address of **VM 210** (Home Assistant).
Keep the box and the collision becomes permanent, so the standby must move into the free `20x` range
(`.203`–`.208`) before its next boot — ideally at the console with the NIC unplugged, so the first boot after
the change cannot land on top of the HA VM.

The standby protects the **OS and the service**, not the data. Converting `md0` to ZFS is destructive, and
[ADR 02](../decisions/02-backup-strategy-restic-blob.md)'s restic repository does **not** cover the Beetle: it
backs up the `lab` host's SSD, and Longhorn persistent volumes are explicitly deferred to Velero. So the
default rollback for the migration window is **OS/service recovery only** — boot the standby, restore the OMV
install, re-point consumers. A genuine *data* rollback needs a **separately staged and verified copy** of the
Beetle working set. The ML110's `md0` is a RAID1 of 2× 500 GB, so it offers **~500 GB usable**, not 1 TB;
whether the working set fits in that is an open question below.

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
| **NFSv4 `krb5p` + Kerberos SMB** | ✅ [ADR 34](../decisions/34-lan-tls-only.md) compliance becomes a supported product feature rather than a plugin hunt — but **not a toggle**: it still needs a directory service, a Kerberos realm and keytabs configured (the [ADR 43](../decisions/43-freeipa-domain-realm.md) FreeIPA realm), so the gain is *support*, not zero setup |
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
- **Resilver on this media is not a selling point.** The last mdadm resync took **~2 h 16 m** at ~120 MB/s
  (`finish=135.6min`, 2026-10-17, [runbook 38](../runbooks/38-nas-disk-replacement.md)) — the *six-day*
  2026-10-11 → 17 window was the whole failed-member replacement (self-test, `badblocks -w`, then resync), not
  the resync itself. A ZFS resilver is *more* random-access intensive than mdadm's sequential rebuild, so
  "ZFS heals a degraded mirror faster" is not true on 2× 2.5″ drives. No ECC either way, so that comparison is
  a wash.
- **No in-place conversion.** mdadm + XFS cannot become a ZFS pool. The array is destroyed and its contents
  restored from a **separately staged copy** — [ADR 02](../decisions/02-backup-strategy-restic-blob.md)'s
  restic repo does not hold the Beetle's data — which also means the *restore path gets exercised*, a genuine
  side benefit.
- **Documentation churn.** Supersedes ADR 29, rewrites [runbook 32](../runbooks/32-beetle-m3-omv-setup.md) and
  [runbook 38](../runbooks/38-nas-disk-replacement.md), plus the Caddy `omv.internal` site, state docs and
  role exclusions.

## Options

| Option | What it is | Verdict |
|---|---|---|
| **A. Keep the ML110 on OMV as an ad-hoc / emergency NAS** | Powered off, OMV 8.3 and `md0`/`md1` intact; boot it when the Beetle is down, when a restore needs a second endpoint, or as the last look-before-you-leap reference. Vacates `.210` for VM 210 and takes a free `20x` address | ✅ **Held as the safety net** — decided 2026-11-07. It is not a trial target and its data is not scratch |
| **B. ZFS under the existing management** | OMV's `openmediavault-zfs` plugin, or plain Debian 13 + `zfs-dkms` + Samba/NFS managed by Ansible | Keeps [ADR 10](../decisions/10-ansible-host-config.md)/[27](../decisions/27-monitoring-strategy.md)/[36](../decisions/36-log-collector-fluentbit.md) intact and still gains ZFS — the fallback if the appliance model turns out to be the expensive part |
| **C. Full TrueNAS cutover on the Beetle** | Wipe and install TrueNAS, create a ZFS mirror on the two 1 TB drives, re-point NFS/SMB, carve `nas` out of uniform automation | ⭐ **Primary direction** — what the operator actually wants to have run in the lab. Accepts the appliance tax knowingly, and needs the 16 GB upgrade |
| **D. Stay on OMV, tighten it** | Add a restic `check --read-data` schedule, keep the monthly scrub, verify SMART alerting reaches Netdata | Always on the table — nothing is broken today |
| **A2. Rehearse before the cutover** | TrueNAS in a VM on `pve2` with a passed-through disk, or on a spare SSD in the Beetle's free SATA ports (**5 total**: 1 OS + 2 data), building a throwaway pool | Not a substitute for C — a **rehearsal** for the UI, the pool layout and the NFS/SMB/ACL screens, so the cutover day is the second time you have seen them |

**Leaning: C**, with **A2** as the pre-cutover rehearsal and **B** as the fallback if the appliance proves to
be more obstacle than product. The ML110 (**A**) is deliberately *not* a trial target — it is what makes C
survivable.

## Cutover shape (option C)

1. **Measure, then decide the rollback.** What is actually on `md0` — datasets, the restic repo, Longhorn
   snapshot usage — and does it fit in the ML110's **~500 GB usable** `md0` (RAID1 of 2× 500 GB)? That single
   number decides whether the standby is a data rollback or only an OS/service rollback.
2. **Verify the rollback before destroying anything.** Whatever step 1 chose — a staged copy of the Beetle
   working set, or OS/service recovery only — prove it *before* the pool is destroyed. A fresh
   `restic check --read-data` against [ADR 02](../decisions/02-backup-strategy-restic-blob.md)'s Azure Blob
   repo verifies the *other* integrity layer (the `lab` host), **not** the NAS rollback. An unverified backup
   is not a rollback.
3. **Buy the RAM.** One 8 GB DDR4 SODIMM → 16 GB, before the appliance is judged.
4. **Rehearse (A2)** — the TrueNAS installer, a mirror pool, the dataset/share/ACL screens, an NFS export and
   an SMB share, on a VM or a spare disk, so nothing is being learned for the first time during an outage.
5. **Cut over.** TrueNAS onto the SanDisk SSD; `md0` re-pooled as a ZFS mirror. **Rollback stops here**: after
   the pool conversion the way back is the staged copy from step 1 (or a restore of the OMV install for
   OS/service only), not a reboot of the old install.
6. **Re-point consumers** — the Longhorn NFS export, the restic SMB landing, the `omv.internal` Caddy site
   (rename or re-TLS it), `nas.internal` and `.209` unchanged.
7. **Make the automation exception explicit** — `playbook-nas.yml` applies `common`, `ca_trust`, `security`,
   `nut_client`, `netdata` and `fluentbit`, and the first four install Debian packages and manage
   systemd/UFW/`fleetadm`. Removing only the two collectors does **not** make the host safe to run through the
   existing playbook, so the exception must cover the **whole playbook**: either exclude `nas` from it entirely
   and define a supported TrueNAS-specific path, or document a per-role exclusion including the NUT client mode
   (TrueNAS ships a native UPS service, so [ADR 39](../decisions/39-nut-host-native.md) is unaffected). Amend
   [ADR 27](../decisions/27-monitoring-strategy.md)/[36](../decisions/36-log-collector-fluentbit.md) with the
   documented exception.
8. **Record it** — a superseding ADR (TrueNAS on the Beetle, ML110 retained as standby) plus a rewritten
   [runbook 32](../runbooks/32-beetle-m3-omv-setup.md); do not edit ADR 29 into a different decision.

## Open questions

- **What is the actual goal** — ZFS fluency, appliance operating experience, or "a NAS that looks like what a
  company would buy"? All three point at C; the question is which one must not be sacrificed, because C gives
  the third and the second, and gives ZFS with the most ceremony.
- **Would the lab rather have ZFS on `pve2`** (where [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md)
  already wants a `zfspool`) than on the NAS? ZFS replication between them then becomes a second backup copy.
- **What does the standby hold** — just the intact OMV install (OS/service rollback), or a separately staged
  copy of the NAS working set on `md0` (a real data rollback for the migration window, if it fits in the
  **~500 GB usable** RAID1)? This decides how long the cutover window can safely be.
- **How is the standby kept honest** — a box that is never booted is a rumour of a backup. What is the
  periodic test (boot, mount, serve one file, power off), and is it acceptable that it appears in neither
  Netdata nor the Fleet inventory while off?
- **Which `20x` address** the standby takes (`.203`–`.208` are free) — and is the change made at the console
  with the NIC unplugged, so the first boot at the new address cannot collide with VM 210 on `.210`?
- **If cutover happens, what is the restore rehearsal** — from Azure Blob (slow) or from a staged copy on
  `lab` or the standby? How long is the NAS's NFS export offline for Longhorn?
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
- **A cold standby rots silently.** Powered off, outside Netdata and the inventory, with 2010-era drives and a
  4 GB ceiling — it is a comfort object unless it is booted and exercised *before* it is needed. Budget the
  test just before the cutover, not after, and expect the drives to need a check when it wakes up.
- **The standby contradicts ADR 29 as written.** ADR 29's consequence is "the ML110 retires once the Beetle's
  array is verified", and [`docs/overview.md`](../overview.md) plans to "retire the ML110 and release `.210`".
  Retaining it is a real, small reversal and needs the superseding ADR to say so — not a quiet prose edit. It
  also makes [ADR 31](../decisions/31-static-address-scheme.md)'s ".210 stays occupied *until retirement*" a
  permanent state, so both ADRs need an amendment.
- **Two NAS truths in the docs** if OMV and ZFS paths are both documented without one superseding the other.

## References

- [ADR 29 — NAS backup target, Beetle M-III (OpenMediaVault)](../decisions/29-nas-backup-target-beetle-m3-omv.md) — the decision this would supersede, including the "no ZFS" reasoning inherited from ADR 23
- [ADR 23 — NAS on the HP ProLiant ML110](../decisions/23-nas-on-ml110.md) — origin of the RAM-ceiling argument (4 GB DDR2, no longer the constraint)
- [Research 32 — Beetle M-III hardware diagnostic](../research/32-wincor-beetle-m3-hardware-diagnostic.md) — CPU, RAM slots, 5 SATA ports, drive serials
- [Research 44 — OMV identity integration](../research/44-omv-identity-integration.md) — the OMV user-model wall TrueNAS' directory integration would remove
- [ADR 34 — LAN TLS only](../decisions/34-lan-tls-only.md) — the NFSv4 `krb5p` / encrypted SMB requirement
- Upstream: [TrueNAS hardware guide](https://www.truenas.com/docs/scale/25.10/gettingstarted/scalehardwareguide/) · [OpenZFS docs](https://openzfs.github.io/openzfs-docs/) · [OMV ZFS plugin](https://docs.openmediavault.org/en/stable/administration/storage/zfs.html)
