# Idea 06 — Homelab Energy Monitoring via Zigbee

> Monitor the homelab's own power consumption as an independent, always-on system — per-device **Zigbee energy plugs** across the key nodes, with the data available to the lab's monitoring stack and to the homelab AI agent — decoupled from Home Assistant.

**Status**: 🧠 Idea — research 27 done, no hardware acquired  
**Date**: 2026-08-15  
**Research**: [Research 27 — Zigbee energy monitoring](../research/27-zigbee-energy-monitoring.md) — the detailed write-up (devices, coordinator, stack/protocol comparison, metrics architecture, AI-agent access, prices)  
**Related**: [Idea 05 — Home Assistant on a Thin Client](05-home-assistant-thin-client.md) / [Research 26](26-home-assistant-thin-client.md) / ADR 25 — this rides on the **same Zigbee mesh, coordinator, and Mosquitto/Z2M containers** as the Home Assistant node

---

## Context

Home Assistant is joining the lab as a dedicated thin-client node (idea 05, ADR 25 Proposed). Alongside it, the lab should know **what its own infrastructure draws**, per node — as an independent, always-on capability that does not depend on Home Assistant's availability or restarts, and that the homelab AI agent can read (and safely control) directly. The how — devices, stack, architecture — lives in [research 27](../research/27-zigbee-energy-monitoring.md).

## Goal

- Per-device visibility of homelab power draw (compute, NAS, network, edge).
- Independent of Home Assistant — monitoring and AI-agent access keep working whether or not HA is up.
- Data available to the lab's monitoring stack and to the AI agent, with control kept separate from analytics.
- Low-power, local Zigbee devices — no cloud dependency.

## Hardware direction

**Zigbee energy plugs + a USB Zigbee coordinator** — see [research 27](../research/27-zigbee-energy-monitoring.md) for the specific products, prices, and the rejected alternatives (per-outlet metering power strips don't exist; classic gateways are wrong for HA; per-outlet metering PDUs are overkill).

## Key decisions to make (open questions)

1. Which Zigbee integration stack to standardize on — and the starting path.
2. Where the stack runs — and where the existing Prometheus/Grafana live.
3. What to buy and when — starter set vs full coverage; bundle with the idea-05 hardware order.
4. How the AI agent consumes the data — control vs read-only analytics, kept separate.
5. Which homelab nodes to instrument first.
6. How this fits the existing observability (Azure Monitor via Arc) and backup model.

## Lifecycle

🧠 **Idea** → 📋 **Planned** (scoped + ADR in progress) → 🔨 **Implementing** → ✅ **Done**.
New hardware + metrics architecture — expect a decision (research 27 → ADR, likely tied to ADR 25) before acquisition.

## References

- [Research 27 — Zigbee energy monitoring](../research/27-zigbee-energy-monitoring.md) — the detailed write-up
- [Idea 05 — Home Assistant on a Thin Client](05-home-assistant-thin-client.md) — the HA node this rides alongside
- [ADR 25 — Home Assistant on a dedicated thin-client node](../decisions/25-home-assistant-thin-client.md) — Proposed
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — likely Prometheus home
- [ADR 23 — NAS on the ML110 (OMV)](../decisions/23-nas-on-ml110.md) — plugged NAS node
- [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md) — Wyse 3040 edge
