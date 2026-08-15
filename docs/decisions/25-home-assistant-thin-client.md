# Home Assistant on a Dedicated Thin-Client Node (Wyse 5070 + Proxmox VE)

**Date:** 2026-08-14
**Status:** Proposed

---

## Context

The homelab has a clean role split: **M910q** = compute (k3s, ADR 22), **ML110** = storage-only OMV NAS (ADR 23), **Wyse 3040** = edge ingress (ADR 24). Home automation is not yet part of the lab. Research ([idea 05](../ideas/05-home-assistant-thin-client.md) → [research 26](../research/26-home-assistant-thin-client.md)) settled the direction for a dedicated smart-home node:

- Home Assistant needs a **central home location** for good Zigbee mesh coverage — the M910q sits in a poor radio spot.
- Running Zigbee2MQTT/MQTT as Home Assistant **add-ons** would drop the Zigbee mesh on every Home Assistant restart.
- Keeping IoT off k3s avoids USB `hostPath`/`nodeSelector` complexity and keeps the cluster purely application.

## Decision

Adopt a dedicated, fanless **Dell Wyse 5070** (Celeron J4105, 2× DDR4 SO-DIMM, M.2 SATA 2280) as a Home Assistant node running **Proxmox VE**:

- **VM 100** — Home Assistant OS (2 vCPU / 4 GB RAM)
- **LXC 101** — Mosquitto MQTT broker (1 vCPU / 256 MB)
- **LXC 102** — Zigbee2MQTT (1 vCPU / 512 MB, USB Zigbee coordinator passed through)
- **8 GB RAM** (16 GB future-proof), **M.2 SATA SSD 64–256 GB** (128 GB practical pick; 64 GB sufficient)
- Proxmox managed via **Ansible `community.proxmox`** (ADR 10 pattern)
- **Netdata** on the Proxmox host, streaming metrics to the M910q Netdata Parent (Tier B, [ADR 27](27-monitoring-strategy.md))

The Wyse 5070 is preferred over the Futro S740 on **design/look** (both run the same J4105; the S740's claimed PCIe x4 slot was a Gemini error) and over the M600 on performance and RAM.

**Proposed → Accepted:** this ADR becomes Accepted once the "dedicated node vs Home Assistant-as-a-k3s-container" trade-off (open question in research 26) is closed and the hardware is purchased.

## Consequences

- Home Assistant and its Zigbee/MQTT mesh are **independent of Home Assistant restarts** and of k3s churn on the M910q.
- M910q k3s stays purely application — it connects to the MQTT broker over LAN; no USB/nodeSelector complexity.
- Second thin-client node to manage — needs a new Ansible provisioning path (Proxmox + VM/LXC); another always-on box (~4–6 W).
- Node placement is tied to a living-space location for radio coverage (design/look preference considered).
- Proxmox adds a virtualization layer + admin overhead vs bare-metal Home Assistant OS, offset by snapshots, `vzdump` backups, LXC isolation, and USB passthrough.
- Disk constrained to **M.2 SATA** (no NVMe); the 16 GB eMMC is rejected (write endurance + size).

### Alternatives Considered

- **Lenovo M600** — ~2.5–3× slower, single DDR3L slot (8 GB max), fan. Rejected.
- **Fujitsu Futro S740** — same J4105 and often cheaper in PL, but no expansion slot (claimed PCIe x4 was a Gemini error) and boxier. Rejected on design/look.
- **HA on the M910q (k3s container)** — no new hardware, but poor radio placement and couples IoT to cluster lifecycle.
- **Bare-metal Home Assistant OS on the Wyse 5070** — simpler, but loses snapshots, whole-VM backups, LXC isolation, and USB passthrough.
- **Zigbee2MQTT/MQTT on the Wyse 3040 edge** — the 3040's 2 GB/8 GB cannot host Proxmox; rejected.

---

## References

- [Research 26 — Home Assistant on a thin client](../research/26-home-assistant-thin-client.md) — full hardware/architecture analysis
- [Idea 05 — Home Assistant on a Thin Client](../ideas/05-home-assistant-thin-client.md)
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — cluster that stays application-only
- [ADR 23 — NAS on the ML110 (OMV)](../decisions/23-nas-on-ml110.md)
- [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md) — the pattern for this ADR
