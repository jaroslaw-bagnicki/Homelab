# NAS Backup Target — Wincor Beetle M-III (OpenMediaVault)

**Date:** 2026-09-05
**Status:** Accepted
**Supersedes:** [ADR 23](23-nas-on-ml110.md)

---

## Context

[ADR 23](23-nas-on-ml110.md) repurposed a retired **HP ProLiant ML110 G5** as the homelab
NAS backup target. That choice was driven by **zero acquisition cost**, and its known cost
was power and noise: ~80 W idle (~€150–200/yr) and a 3-fan chassis — the loudest box in the
lab. It was always a stopgap.

[Idea 01c](../ideas/01c-nas-backup-target-wincor-beetle.md) scoped a **Wincor Beetle M-III**
POS terminal as the successor, on **Unraid**. The **2026-09-12 Phase 0 audit**
([research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md)) settled the successor
direction — the Beetle replaces the ML110 as the backup target, on **2× Seagate
(1 parity + 1 data = 1 TB) + the SanDisk X600 cache** — and confirmed idea 01c's platform
premise (the offered **Skylake / H110 / LGA1151 / DDR4** platform, Pentium G4400, 8 GB DDR4).

The **OS choice stayed open past the audit**: Unraid was the working direction, gated on its
paid licence, with OMV as the fallback ([issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)).
It was confirmed as **OMV** on 2026-09-12 — that part is what this ADR adds to the audited direction.

## Decision

**The Wincor Beetle M-III becomes the homelab NAS backup target, running OpenMediaVault —
Unraid dropped.** The ML110 retires once the Beetle's array is verified.

- **OS: OMV, not Unraid.** Removes the licence cost and keeps the NAS on the
  **Debian-family** path already proven on the ML110 (ADR 23) — the same mdadm + XFS/ext4
  design, the same runbooks, and no per-OS exception to the [ADR 27](27-monitoring-strategy.md)
  `netdata` role. Unraid's advantages (mixed-size arrays, add-a-drive, running from USB) are
  not needed for a two-disk mirror.
- **Storage design carries over — mdadm RAID1, no ZFS**, on ADR 23's reasoning: a thin RAM
  budget, per-disk `smartctl` visibility, and arrays that import on any Linux box.
- **The NAS stays the local backup target** — NFS for Longhorn volume snapshots (fires with
  k3s, [ADR 22](22-k3s-arc-homelab.md)) and SMB backup landing (ADR 02). The successor work
  moves off the ML110 (issues [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) /
  [#62](https://github.com/jaroslaw-bagnicki/Homelab/issues/62)).
- **Unraid stays a migration path, not a rejected option** — idea 01 notes the disks can be
  imported if the licence ever becomes worth it.

## Consequences

- **Licence cost avoided**, and no USB-boot / flash-wear management.
- **One OS across the NAS estate** — OMV tooling and runbooks 22/23/26 transfer directly.
- **Debian-family, so not a monitoring exception** — the Beetle child fits the ADR 27 role
  parameterisation, unlike the Unraid path.
- **Capacity growth is less flexible than Unraid** — expansion means a second mirror pair or
  a PCIe SATA HBA, not "add a drive of any size".
- **Phase 0 is verified on the delivered unit** — platform (Skylake / H110 / DDR4), CPU, RAM
  and NIC are confirmed in [research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md);
  the PSU label, BIOS walk, HDD SMART and Memtest remain as pre-install checks.
- **Interim dependency on the ML110** — it remains the live backup target until the Beetle
  array is verified, so its power/noise saving is not realised until retirement.
- **The Beetle's active-PFC PSU constrains UPS coverage** — a modified-sine unit must be
  proven by a pull-the-plug test, or the box sits on non-battery outlets
  ([idea 09](../ideas/09-ups-nut-home-assistant.md)).

### Alternatives Considered

- **Unraid** (paid, ~$60–130) — the original direction in idea 01c: the best mixed-disk UX,
  cache pooling, USB boot. Deferred: the licence buys flexibility a two-disk mirror does not
  need, and it would add a per-OS exception to the monitoring role.
- **Keep the ML110** — rejected: ~80 W idle and 3-fan noise for a two-disk array, and the
  successor is already owned.
- **TrueNAS / ZFS** — rejected in ADR 23 and unchanged here (the RAM ceiling makes it a poor
  fit).

---

## References

- [ADR 23 — NAS on the HP ProLiant ML110 (OpenMediaVault)](23-nas-on-ml110.md) — superseded by this ADR
- [Idea 01c — Homelab NAS: Wincor Beetle M-III](../ideas/01c-nas-backup-target-wincor-beetle.md)
- [Research 32 — Beetle M-III hardware diagnostic](../research/32-wincor-beetle-m3-hardware-diagnostic.md) — Phase 0 audit (platform confirmed; PSU/BIOS/HDD checks pending)
- [ADR 27 — Monitoring strategy](27-monitoring-strategy.md) — the shared `netdata` role this keeps the Beetle inside
- [ADR 22 — k3s + Azure Arc](22-k3s-arc-homelab.md) — Longhorn NFS backup target
