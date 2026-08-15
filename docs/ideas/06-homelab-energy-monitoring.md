# Idea 06 — Homelab Energy Monitoring via Zigbee

> Monitor homelab power consumption with **Nous A1Z Zigbee energy plugs** + a **Sonoff ZBDongle-P** USB coordinator, feeding an **independent Zigbee2MQTT → mqtt2prometheus → Prometheus → Grafana** path — decoupled from Home Assistant, with power data (and optional control) exposed to the homelab AI agent.

**Status**: 🧠 Idea — research 27 done, no hardware acquired  
**Date**: 2026-08-15  
**Research**: [Research 27 — Zigbee energy monitoring (Nous A1Z + Prometheus)](../research/27-zigbee-energy-monitoring.md) — full Gemini-thread write-up (products, coordinator, ZHA vs Z2M, metrics architecture, AI-agent access)  
**Related**: [Idea 05 — Home Assistant on a Thin Client](05-home-assistant-thin-client.md) / [Research 26](26-home-assistant-thin-client.md) / ADR 25 — this rides on the **same Zigbee mesh, coordinator, and Mosquitto/Z2M containers** as the Home Assistant node

---

## Context

Home Assistant is joining the lab as a dedicated thin-client node (idea 05, ADR 25 Proposed). Alongside it, the user wants to **monitor the homelab's own power consumption** as an independent system — not tied to Home Assistant's availability or restarts. The thread picks the hardware (Nous A1Z plugs, Sonoff ZBDongle-P) and settles the target architecture: **Z2M hosted independently → `mqtt2prometheus` → Prometheus → Grafana**, with the AI agent consuming both MQTT (control) and the Prometheus API (analytics).

## Goal

- Buy a **Nous A1Z USED 4-pack (~109 zł, noussmart.pl promo)** as the starter set + a **Sonoff ZBDongle-P (~90–100 zł)** with a USB extension cable.
- Place plugs on the key homelab nodes (M910q, ML110 NAS, switch, router) to measure per-device draw.
- Run **Zigbee2MQTT independently of Home Assistant** (per idea 05's LXC layout), expose JSON over **Mosquitto MQTT**.
- Bridge MQTT → **Prometheus** via `mqtt2prometheus`; visualize in **Grafana**.
- Give the **AI agent** read-write control via a restricted **MQTT ACL** account, and read-only analytics via the **Prometheus HTTP API**.

## Hardware direction (from research 27)

| Option | Verdict | Reason |
|---|---|---|
| **Nous A1Z USED 4-pack (109 zł)** | ✅ Pick | ~27,25 zł/unit vs ~55–60 zł retail; native Z2M (`TS011F`/`_TZ3000_26aw2vkh`) + ZHA; entities W/A/V/kWh; acts as Zigbee Router; compact on 45° strips |
| Individual A1Z/A7Z plugs (5×) | Fallback | ~50–60 zł each — the same plugs bought singly (no promo) |
| Nous A11Z power strip | ❌ Rejected | Per-outlet **switch** only, **total** measurement (single BL0942 at input) — no per-outlet energy data |
| Switched metered PDU (APC/CyberPower) | ❌ Rejected | True per-outlet metering but SNMP/HTTP (not Zigbee), IEC sockets, from ~1200 zł |
| Classic Wi-Fi/Tuya gateway (Nous E1) | ❌ Rejected | Cloud-bound vendor architecture — wrong for HA/Z2M; the USB coordinator is the standard |
| **Sonoff ZBDongle-P** | ✅ Pick | CC2652P, ~90–100 zł, gold standard in Z2M + ZHA, external antenna + aluminium shielding |

## Key decisions to make (open questions)

1. **ZHA vs Zigbee2MQTT for the start**: ZHA = instant go-live with the A1Z set; Z2M = the long-term independent architecture — start with ZHA and migrate, or go straight to Z2M?
2. **Where Mosquitto/Z2M live**: research 26 puts them as LXC containers on the Wyse 5070 next to the Home Assistant VM — confirm `mqtt2prometheus` also lands there, or on the k3s cluster (M910q) where Prometheus already runs.
3. **Where Prometheus/Grafana run**: verify the existing Prometheus/Grafana deployment (M910q k3s?) and scrape target (`mqtt2prometheus:9641/metrics`).
4. **Purchase timing**: the 109 zł A1Z USED promo — grab while available, or wait to bundle with the idea-05 hardware purchase (Wyse 5070 + ZBDongle-P)?
5. **AI agent access**: which agent and how — wire MQTT ACL + Prometheus API into the agent's toolset; keep control read-write separate from analytics read-only.
6. **Coverage target**: which homelab nodes get a plug first (M910q, ML110 NAS, switch/router, future Wyse 5070 + 3040)? Per-outlet measurement needs one plug per device (no per-outlet strips exist).
7. **Monitoring scope vs restic/Blob observability**: how this metrics path coexists with Azure Monitor via Arc (ADR 04/09) and the existing observability stack.

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
