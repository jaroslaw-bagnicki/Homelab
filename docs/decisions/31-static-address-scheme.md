# Static Address Scheme — Server and Guest Blocks

**Date:** 2026-09-13
**Status:** Proposed

---

## Context

The homelab lives on one flat `192.168.2.0/24` subnet behind the Tenda Nova mesh, which cannot
trunk VLANs — every device shares one broadcast domain, so addresses are handed out by convention
rather than by a per-class DHCP scope ([research 24](../research/24-network-topology-design.md)).
Its tens-blocks were introduced as `20x` server / `21x` NAS / `22x` LLM / `23x` switch / `24x` edge.

Two things have moved since:

- **The HA node grew a hypervisor.** The Wyse 5070 runs Proxmox VE
  ([ADR 25](25-home-assistant-thin-client.md), [runbook 28](../runbooks/28-ha-proxmox-node.md)) with
  a VM and three LXCs planned, none of which had a home in the scheme.
- **The NAS role left the `21x` block.** The ML110 was the block's only member
  ([ADR 23](23-nas-on-ml110.md)) and is retiring ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)),
  while its successor is a physical server in its own right. Reusing the vacated block for virtual
  guests renumbers nothing — and the NUT container ([ADR 30](30-ups-nut-graceful-shutdown.md))
  needed an address immediately.

## Decision

**Address static devices by class — `20x` physical servers, `21x` Proxmox guests — and derive the
guest addresses from the VMID.**

| Block | Class | Members |
|---|---|---|
| `200–209` | physical servers | `lab` M910q `.200` · HA node `.201` · Beetle NAS `.202` |
| `210–219` | Proxmox guests on the HA node | rule `.210 + (VMID - 100)`: VM 100 `.210`, LXC 101 `.211`, LXC 102 `.212`, LXC 103 `.213` |
| `220–229` | LLM server (Phase 2) | — |
| `230–239` | switch management | TL-SG108E `.230` |
| `240–249` | edge/ingress appliances | Wyse 3040 `.240` |

With one hypervisor in play, a guest is addressed **`.210 + (VMID - 100)`** — its address follows the
Proxmox ID it already has instead of an independent numbering. Everything else stays on mesh DHCP.

## Consequences

- **A guest's address is predictable from its VMID** — no lookup for the common case, and a new
  guest's address is known before it exists.
- **Each role sits in a block of its own class.** The Beetle takes a `20x` address as the physical
  NAS; the ML110 vacates `.210` when it retires.
- **The rule assumes one hypervisor.** VMID→address resolves uniquely only while a single Proxmox
  host exists; a second host with its own VMID 100 would collide and needs its own block. This is
  the assumption to revisit first if a second hypervisor appears.
- **`.210` stays occupied until the ML110 is retired** — powered off is not the same as released.
  It is configured static at `.210` ([runbook 23](../runbooks/23-ml110-omv-setup.md)), so any boot
  before retirement, most likely the data migration onto the Beetle, collides with the HA VM:
  change its address or set it to DHCP *before* that boot.
- **Only infrastructure is static.** The house, the work laptop dock, and anything without a
  reservation keep taking a DHCP lease from the mesh.
- **The scheme lives in one place per audience** — this ADR owns the policy,
  [research 24](../research/24-network-topology-design.md) carries the allocation table, and
  runbooks reference them instead of restating addresses.

### Alternatives Considered

- **Contiguous allocation (`200–204`)** — no headroom per class: a second NAS or a second guest
  forces renumbering of live devices.
- **Keep `21x` for NAS and move guests to a new block (`25x`)** — leaves `.210`–`.219` idle although
  the NAS role is already carried by a `20x` address, and adds a block the mesh has no reason to
  distinguish.
- **Guest addressing independent of VMID (sequential from `.210`)** — decouples two numbering
  systems at the cost of a lookup every time a guest is created or its address is needed.
- **DHCP reservations instead of static configuration** — one place to manage addresses, but they
  would live in the mesh UI rather than beside the runbooks that depend on them, and the guest
  addresses still have to be derived from the VMIDs on the host.

---

## References

- [Research 24 — Homelab Network Topology & Design](../research/24-network-topology-design.md) — allocation table and block rationale
- [Runbook 29 — UPS graceful shutdown (NUT on the HA node)](../runbooks/29-nut-ups-shutdown.md) — first consumer of the guest rule (LXC 103 `.213`)
- [ADR 23](23-nas-on-ml110.md) — the ML110's `.210` · [ADR 25](25-home-assistant-thin-client.md) — the HA node · [ADR 29](29-nas-backup-target-beetle-m3-omv.md) — Beetle NAS · [ADR 30](30-ups-nut-graceful-shutdown.md) — NUT
