# Static Address Scheme — Server and Guest Blocks

**Date:** 2026-09-13
**Status:** Accepted

---

## Context

The homelab lives on one flat `192.168.2.0/24` subnet behind the Tenda Nova mesh, which cannot
trunk VLANs — every device shares one broadcast domain, so addresses are handed out by convention
rather than by a per-class DHCP scope ([research 24](../research/24-network-topology-design.md)).
Its tens-blocks were introduced as `20x` server / `21x` NAS / `22x` LLM / `23x` switch / `24x` edge.

Two things have moved since:

- **The smart-home node grew a hypervisor.** The Wyse 5070 runs Proxmox VE
  ([ADR 25](25-home-assistant-thin-client.md), [runbook 28](../runbooks/28-pve-proxmox-node.md)) with
  a VM and three LXCs planned, none of which had a home in the scheme.
- **The NAS role left the `21x` block.** The ML110 was the block's only member
  ([ADR 23](23-nas-on-ml110.md)) and is retiring ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)),
  while its successor is a physical server in its own right. Reusing the vacated block for virtual
  guests renumbers nothing — and the NUT container ([ADR 30](30-ups-nut-graceful-shutdown.md))
  needed an address immediately.

## Decision

**Address static devices by class — `20x` physical servers, `21x` Proxmox guests — and make a
guest's VMID its address's last octet.**

| Block | Class | Members |
|---|---|---|
| `200–209` | physical servers | `lab` M910q `.200` · `pve` Wyse 5070 `.201` · Beetle NAS `.202` |
| `210–219` | Proxmox guests on the Proxmox VE host | **VM 210** `.210` · **LXC 211** `.211` · **LXC 212** `.212` · **LXC 213** `.213` |
| `220–229` | LLM server (Phase 2) | — |
| `230–239` | switch management | TL-SG108E `.230` |
| `240–249` | edge/ingress appliances | Wyse 3040 `.240` |

The ID and the address are **the same number** — `VM 210` is `.210`, `LXC 213` is `.213` — so
neither needs a lookup or an offset. Everything else stays on mesh DHCP. The IDs are assigned while
the guests are still unbuilt ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) /
[#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)); once a guest exists, changing its ID
is a restore, not an edit.

## Consequences

- **A guest's address needs no derivation** — the ID *is* the address, so `qm list` / `pct list` read
  as the address plan, and a new guest's address is known from the ID it is handed.
- **Each role sits in a block of its own class.** The Beetle takes a `20x` address as the physical
  NAS; the ML110 vacates `.210` when it retires.
- **The numbering follows the addresses, not a shared counter.** A second hypervisor would need its
  **own guest block allocated before it exists** — which is the point: the scheme scales by class, and
  that coupling is what an offset rule (`.210 + (VMID - 100)`) cannot express. `22x` is already the
  Phase 2 LLM server's block, so a second host's guests would need a new one.
- **The address and the ID move together.** Re-addressing a guest means changing its ID as well, and
  Proxmox has no in-place ID change — the guest is restored under the new ID. Accepted because the
  addresses are stable by design: it is the price of the identity.
- **`.210` stays occupied until the ML110 is retired** — powered off is not the same as released.
  It is configured static at `.210` ([runbook 23](../runbooks/23-ml110-omv-setup.md)), so any boot
  before retirement, most likely the data migration onto the Beetle, collides with the HA VM:
  change its address or set it to DHCP *before* that boot. Leaving it occupied is the more expensive
  mistake now — re-addressing the HA VM would cost it its VMID too.
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
- **The offset rule, `.210 + (VMID - 100)`** (VM 100 → `.210`, LXC 103 → `.213`) — keeps Proxmox IDs
  conventional and lets an address change leave the ID alone, but the arithmetic is anchored at ID
  `100`, so a second host's IDs could not map onto its own block, and every address carried a
  derivation step. This was the rule the ADR first carried; the guests were still unbuilt, so the
  identity replaced it at no cost.
- **DHCP reservations instead of static configuration** — one place to manage addresses, but they
  would live in the mesh UI rather than beside the runbooks that depend on them, and the guest
  addresses still have to be derived from the VMIDs on the host.

---

## References

- [Research 24 — Homelab Network Topology & Design](../research/24-network-topology-design.md) — allocation table and block rationale
- [Runbook 29 — UPS graceful shutdown (NUT on the Proxmox VE node)](../runbooks/29-nut-ups-shutdown.md) — first consumer of the guest numbering (LXC 213 `.213`)
- [ADR 23](23-nas-on-ml110.md) — the ML110's `.210` · [ADR 25](25-home-assistant-thin-client.md) — the Proxmox VE host · [ADR 29](29-nas-backup-target-beetle-m3-omv.md) — Beetle NAS · [ADR 30](30-ups-nut-graceful-shutdown.md) — NUT
