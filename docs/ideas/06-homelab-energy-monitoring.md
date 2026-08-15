# Idea 06 — Homelab Energy Monitoring

> Monitor the homelab's own power consumption as an independent, always-on system — per-device **energy-measuring plugs** across the key nodes, with the data available to the lab's monitoring stack and to the homelab AI agent — decoupled from Home Assistant. **Zigbee is the most promising radio option**, but the choice is delegated to research, which compares it against alternatives.

**Status**: 🧠 Idea — research 27 done, no hardware acquired  
**Date**: 2026-08-15  
**Research**: [Research 27 — Zigbee energy monitoring](../research/27-zigbee-energy-monitoring.md) — the full research output  
**Related**: [Idea 05 — Home Assistant on a Thin Client](05-home-assistant-thin-client.md) / [Research 26](../research/26-home-assistant-thin-client.md) / ADR 25

---

## Context

Home Assistant is joining the lab as a dedicated thin-client node (idea 05, ADR 25 Proposed). Alongside it, the lab should know **what its own infrastructure draws**, per node — as an independent, always-on capability that does not depend on Home Assistant's availability or restarts, and that the homelab AI agent can read (and safely control) directly.

**Zigbee looks the most promising** (rich device ecosystem, low-power battery sensors, mains plugs act as mesh routers) — but the radio choice is delegated to [research 27](../research/27-zigbee-energy-monitoring.md), which compares it against alternatives before any decision.

## Goal

- Per-device visibility of homelab power draw (compute, NAS, network, edge).
- Independent of Home Assistant — monitoring and AI-agent access keep working whether or not HA is up.
- Data available to the lab's monitoring stack and to the AI agent, with control kept separate from analytics.
- Historical data retained for analysis — trends, baselines, and longer-range queries by the AI agent.
- Low-power, local devices (radio TBD in research) — no cloud dependency.

## Questions to answer in research

1. Which radio protocol — **Zigbee (most promising)** vs the alternatives — and why.
2. Which integration stack, and whether it can be independent of Home Assistant.
3. Where the stack runs, and where the existing Prometheus/Grafana live.
4. What to buy and when — starter set vs full coverage; bundle with the idea-05 hardware order.
5. How the AI agent consumes the data — control vs read-only analytics, kept separate.
6. Which homelab nodes to instrument first.
7. How this fits the existing observability (Azure Monitor via Arc) and backup model.

## Research

All substance — radio alternatives, devices, stack, metrics architecture, AI-agent access, and open questions — lives in [research 27](../research/27-zigbee-energy-monitoring.md), which this idea references as a whole. The decision will be recorded in an ADR (likely tied to ADR 25).

## Lifecycle

🧠 **Idea** → 📋 **Planned** (scoped + ADR in progress) → 🔨 **Implementing** → ✅ **Done**.
New hardware + metrics architecture — expect a decision (research 27 → ADR) before acquisition.

## References

- [Research 27 — Zigbee energy monitoring](../research/27-zigbee-energy-monitoring.md) — the full research output
- [Idea 05 — Home Assistant on a Thin Client](05-home-assistant-thin-client.md) — the HA node this rides alongside
- [ADR 25 — Home Assistant on a dedicated thin-client node](../decisions/25-home-assistant-thin-client.md) — Proposed
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md)
- [ADR 23 — NAS on the ML110 (OMV)](../decisions/23-nas-on-ml110.md)
- [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md)
