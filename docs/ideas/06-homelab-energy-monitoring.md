# Idea 06 — Homelab Energy Monitoring via Zigbee

> Monitor the homelab's own power consumption as an independent system — per-device **Zigbee energy plugs** on the key nodes, a **USB Zigbee coordinator**, and an independent **Zigbee2MQTT → Prometheus → Grafana** path — decoupled from Home Assistant, with power data (and optional control) exposed to the homelab AI agent.

**Status**: 🧠 Idea — research 27 done, no hardware acquired  
**Date**: 2026-08-15  
**Research**: [Research 27 — Zigbee energy monitoring](../research/27-zigbee-energy-monitoring.md) — the detailed write-up (devices, coordinator, ZHA vs Z2M, metrics architecture, AI-agent access, prices)  
**Related**: [Idea 05 — Home Assistant on a Thin Client](05-home-assistant-thin-client.md) / [Research 26](26-home-assistant-thin-client.md) / ADR 25 — this rides on the **same Zigbee mesh, coordinator, and Mosquitto/Z2M containers** as the Home Assistant node

---

## Context

Home Assistant is joining the lab as a dedicated thin-client node (idea 05, ADR 25 Proposed). Alongside it, the user wants to **monitor the homelab's own power consumption** as an independent system — not tied to Home Assistant's availability or restarts. The direction: per-device **Zigbee energy plugs** on the key homelab nodes, a **USB Zigbee coordinator**, and an independent **Zigbee2MQTT → Prometheus → Grafana** path. Specifics (devices, prices, architecture) live in [research 27](../research/27-zigbee-energy-monitoring.md).

## Goal

- Instrument the key homelab nodes (M910q, ML110 NAS, switch, router, future thin clients) for per-device power draw via **Zigbee energy-measuring plugs**.
- Run **Zigbee2MQTT independently of Home Assistant** (per idea 05's LXC layout), exposing JSON over **Mosquitto MQTT**.
- Bridge MQTT → **Prometheus** and visualize in **Grafana** — independent of Home Assistant restarts.
- Give the **AI agent** read-write control (restricted **MQTT ACL**) and read-only analytics (**Prometheus API**).

## Hardware direction

**Zigbee energy plugs + a USB Zigbee coordinator** — see [research 27](../research/27-zigbee-energy-monitoring.md) for the specific products, prices, and the rejected alternatives (per-outlet metering power strips don't exist; classic gateways are wrong for HA; per-outlet metering PDUs are overkill).

## Key decisions to make (open questions)

1. **Zigbee stack for the start**: native **ZHA** (quick go-live) vs **Zigbee2MQTT** (long-term independent architecture) — and when to migrate.
2. **Where the stack runs**: LXC containers on the HA thin-client node (idea 05) vs the k3s cluster — and where the existing **Prometheus/Grafana** live.
3. **Purchase**: how much to buy up front (starter set vs full coverage) and whether to bundle with the idea-05 hardware order.
4. **AI agent access**: which agent and how — wire **MQTT ACL** (control) + **Prometheus API** (analytics) into the agent's toolset, kept separate.
5. **Coverage scope**: which homelab nodes get a plug first; per-device measurement needs one plug per device.
6. **Coexistence with observability**: how this metrics path fits alongside Azure Monitor via Arc (ADR 04/09) and the restic/Blob backup model.

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
