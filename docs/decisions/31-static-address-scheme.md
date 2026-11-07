# Static Address Scheme — Server and Guest Blocks

**Date:** 2026-09-13
**Status:** Accepted
**Amended:** 2026-11-06 — `pve` → `pve1`; `pve2` takes `.202`; the Beetle NAS moves to `.209`; `pve2`'s guest block is `25x` (`.250–.254`).

---

## Context

The homelab lives on one flat `192.168.2.0/24` subnet behind the Tenda Nova mesh, which cannot
trunk VLANs — every device shares one broadcast domain, so addresses are handed out by convention
rather than by a per-class DHCP scope ([research 24](../research/24-network-topology-design.md)).
Its tens-blocks were introduced as `20x` server / `21x` NAS / `22x` LLM / `23x` switch / `24x` edge.

Two things have moved since:

- **The smart-home node grew a hypervisor.** The Wyse 5070 runs Proxmox VE
  ([ADR 25](25-home-assistant-thin-client.md), [runbook 28](../runbooks/28-pve1-proxmox-node.md)) with
  a VM and three LXCs planned, none of which had a home in the scheme. A second hypervisor (`pve2`)
  now needs its own guest block as well ([ADR 47](47-second-proxmox-node-cluster-qdevice.md)).
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
| `200–209` | physical servers | `lab` M910q `.200` · `pve1` Wyse 5070 `.201` · `pve2` OptiPlex 7050 `.202` · `.203–.208` free · Beetle NAS `.209` |
| `210–219` | Proxmox guests on the `pve1` node | **VM 210** `.210` · **LXC 211** `.211` · **LXC 212** `.212` · **LXC 213** `.213` (retired — NUT host-native, [ADR 39](39-nut-host-native.md)) · **LXC 214** `.214` |
| `220–229` | LLM server (Phase 2) | — |
| `230–239` | switch management | TL-SG108E `.230` |
| `240–249` | edge/ingress appliances | Wyse 3040 `.240` |
| `250–254` | Proxmox guests on the `pve2` node | reserved — `.255` is the broadcast address, so the block has five usable addresses |

The ID and the address are **the same number** — `VM 210` is `.210`, `LXC 214` is `.214` — so
neither needs a lookup or an offset. Everything else stays on mesh DHCP. The IDs are assigned while
the guests are still unbuilt ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) /
[#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)); once a guest exists, changing its ID
is a restore, not an edit.

## Consequences

- **A guest's address needs no derivation** — the ID *is* the address, so `qm list` / `pct list` read
  as the address plan, and a new guest's address is known from the ID it is handed. `pve2` guests
  therefore use VMIDs/CTIDs `250–254`.
- **Each role sits in a block of its own class.** The Beetle takes a `20x` address as the physical
  NAS; the ML110 vacates `.210` when it retires.
- **The numbering follows the addresses, not a shared counter.** A second hypervisor gets its
  **own guest block allocated before it exists** — `pve2` takes `25x` (`.250–.254`), which is the
  last free tens-block in the `/24`. `22x` stays the Phase 2 LLM server's block. The `/24` is now
  full: a third hypervisor would need a second subnet or a VLAN, not a new tens-block.
- **The address and the ID move together.** Re-addressing a guest means changing its ID as well, and
  Proxmox has no in-place ID change — the guest is restored under the new ID. Accepted because the
  addresses are stable by design: it is the price of the identity.
- **The Beetle NAS moved from `.202` to `.209`** on 2026-11-06 so `pve2` can take `.202`; the
  `20x` block still has `.203–.208` free for future physical servers.
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
- [Runbook 29 — UPS graceful shutdown (NUT on the pve1 node)](../runbooks/29-nut-ups-shutdown.md) — the NUT server is now **host-native** on `pve1` (`.201`), so `.213` is free ([ADR 39](39-nut-host-native.md))
- [ADR 23](23-nas-on-ml110.md) — the ML110's `.210` · [ADR 25](25-home-assistant-thin-client.md) — the `pve1` node · [ADR 29](29-nas-backup-target-beetle-m3-omv.md) — Beetle NAS · [ADR 39](39-nut-host-native.md) — NUT host-native
- [ADR 47](47-second-proxmox-node-cluster-qdevice.md) — `pve2`, the `25x` guest block and the two-node cluster
