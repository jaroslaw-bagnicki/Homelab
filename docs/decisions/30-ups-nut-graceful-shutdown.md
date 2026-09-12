# UPS Graceful Shutdown — NUT on the HA Node

**Date:** 2026-09-12
**Status:** Accepted

---

## Context

The lab runs as a fleet across two power strips — the servers (M910q/k3s, Wyse 3040 edge, Wyse 5070
HA, and the incoming Beetle NAS) and the network appliances (switch, mesh node, LTE modem). Nothing
protected it from a brownout, and an unclean stop is the worst outcome for the NAS RAID1 and its
SMB/NFS exports, for Proxmox's VMs/LXCs, and for k3s state.

[Idea 09](../ideas/09-ups-nut-home-assistant.md) carried the analysis — load profile, the Green Cell
model comparison, and the NUT-versus-alternatives discussion. Implementation is tracked in
[issue #111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111).

Three findings on 2026-09-12 pinned the remaining choices:

- **The unit acquired is a Green Cell UPSLM600** — 1000 VA / 600 W, 2× 12 V 7 Ah on a 24 V train,
  modified sine, four outlets.
- **Its USB interface is `0665:5161`** (Cypress/INNO TECH bridge), whose HID report descriptor
  declares usage page **`0xFF00` (vendor-defined)**, not **`0x84` (Power Device)**. NUT's HID Power
  Device driver is therefore structurally unable to drive it, and the unit carries **no serial
  number**.
- **The HA node's Proxmox base is live** ([runbook 28](../runbooks/28-ha-proxmox-node.md)) while the
  Home Assistant OS VM is not yet built ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) /
  [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)), so the HA-side integration cannot be
  in the initial scope.

## Decision

**Drive the shared rail with NUT, run its server in a dedicated LXC on the HA node, and let every
node stop itself on low battery.**

- **NUT.** One mechanism drives a heterogeneous fleet, and it already has a Home Assistant
  integration and a monitoring path.
- **NUT server in a dedicated unprivileged LXC (103) on the HA node's Proxmox** — chosen over
  host-native on the base, for container isolation and config that folds into VM/LXC backups.
- **Driver `nutdrv_qx`**, with `port = auto` plus `vendorid`/`productid`. The vendor-defined usage
  page rules out `usbhid-ups`, and with no serial number there is no stable device path to name.
- **The Proxmox host runs `nut-client` as the sole `upsmon` primary**; `lab` and `edge` are
  secondaries. An unprivileged LXC cannot power off its own host, so the hypervisor stops itself and
  Proxmox then stops the guests in order.
- **Shutdown triggers on low battery (`LB`)**, not on a runtime countdown.
- **The Beetle M-III becomes the NAS client once it stands** ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)).
- **The Home Assistant NUT integration is deferred** until the HA OS VM exists.

## Consequences

- **Every node reacts to the same UPS state** — the NAS array and its exports, the Proxmox guests and
  k3s get orderly stops instead of a power cut.
- **The UPS state is served on the LAN by NUT** — nothing workstation-side sits in the path, so the
  telemetry route into Netdata/Prometheus stays open ([ADR 27](27-monitoring-strategy.md),
  [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73)).
- **The LXC choice does not remove host-side NUT** — the hypervisor still needs its own `upsmon`, and
  the container has to be running for the host to know the battery state at all.
- **USB passthrough into an unprivileged container is the fragile part.** On attach the kernel's
  `usbhid` claims the interface, so handing it to `nutdrv_qx` has to be proven
  ([runbook 29](../runbooks/29-nut-ups-shutdown.md) §3). If the container cannot take the device, the
  fix is a host udev unbind or a privileged container — neither changes this decision, only its
  implementation.
- **No outlet power-off** — the driver dies with its container, so the UPS is left to drain rather
  than being told to cut power.
- **Modified sine constrains coverage** — harmless for the external DC bricks, but the Beetle's
  active-PFC supply has to clear a pull-the-plug test; a pure-sine unit is the fallback
  ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)).
- **Recovery is manual until decided otherwise** — after a full drain the nodes stay off, so BIOS
  AC-restore behaviour is an open per-node choice.
- **The UPS's own consumption is material** — a ~14.2 W standby figure (unverified buyer report)
  against a fleet that idles around 60–85 W.
- **The router is not covered** — OPNsense is FreeBSD and needs its own client path
  ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)).

### Alternatives Considered

- **NUT server host-native on the base** (idea 09's recommendation) — simpler: no USB passthrough, no
  host-side client, no boot ordering to reason about. Not taken; the LXC route instead pays for
  isolation with the host-side `upsmon`, the passthrough, and a container that must be up for the
  host to react.
- **NUT server as a k3s workload on the M910q** — rejected: USB device-plugin plumbing, and power
  monitoring that depends on cluster health.
- **`usbhid-ups`** — impossible on this unit: it requires the standard HID Power Device usage page.
- **Runtime-triggered shutdown** — unavailable: the unit exposes no runtime estimate.

---

## References

- [Issue #111 — UPS + NUT graceful shutdown](https://github.com/jaroslaw-bagnicki/Homelab/issues/111) · [Idea 09 — UPS with NUT + Home Assistant](../ideas/09-ups-nut-home-assistant.md)
- [Runbook 29 — UPS graceful shutdown (NUT on the HA node)](../runbooks/29-nut-ups-shutdown.md)
- [ADR 25](25-home-assistant-thin-client.md) — the HA node · [ADR 27](27-monitoring-strategy.md) — monitoring · [ADR 28](28-fleet-admin-account-and-key.md) — fleet admin account · [ADR 29](29-nas-backup-target-beetle-m3-omv.md) — Beetle NAS
- [Network UPS Tools](https://networkupstools.org/) — `nutdrv_qx`, `upsd`, `upsmon`
