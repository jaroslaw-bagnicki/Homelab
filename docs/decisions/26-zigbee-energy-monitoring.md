# Zigbee Energy Monitoring — Z2M → Prometheus, Independent of Home Assistant

**Date:** 2026-08-15
**Status:** Accepted

---

## Context

The lab needs per-node power-consumption monitoring of its own infrastructure — an independent, always-on capability that does not depend on Home Assistant's availability or restarts, with data available to the homelab monitoring stack and the AI agent. The full analysis (radio/protocol comparison, device & coordinator selection, prices, architecture) is in [research 27](../research/27-zigbee-energy-monitoring.md) · [idea 06](../ideas/06-homelab-energy-monitoring.md).

## Decision

Adopt **Zigbee + Zigbee2MQTT** for homelab power monitoring, decoupled from Home Assistant:

- **Radio**: Zigbee — over Z-Wave, Matter/Thread, and Wi-Fi/Tasmota (MQTT-native, low-power, richest device ecosystem for the lab).
- **Stack**: **Zigbee2MQTT**, not ZHA — fully independent of HA; every device state is plain JSON over MQTT, which satisfies the must-have of direct homelab-infra + AI-agent integration.
- **Coordinator**: **Sonoff ZBDongle-P** (CC2652P / Z-Stack) — the most mature, stable path for Z2M.
- **Devices**: **Nous A1Z** energy plugs (W/A/V/kWh); starter set = **4× A1Z** (USED 4-pack, ~109 PLN), expandable to one plug per key node later.
- **Path**: Z2M → Mosquitto → `mqtt2prometheus` → Prometheus → Grafana; AI-agent access via restricted MQTT ACL (control) + Prometheus API (read-only).
- **Home Assistant is optional** — it may join the same broker later; monitoring runs standalone (e.g. bootstrap on the M910q, research 27 §7.1).

## Consequences

- Monitoring is **independent of HA** — no single point of failure tied to the HA instance.
- Prometheus retains **historical** data for trends, baselines, and AI-agent queries.
- **MQTT-centric** — any consumer (Grafana, HA, AI agent, exporter) reads the same broker.
- The Zigbee mesh + ZBDongle-P coordinator is **shared with the future Home Assistant node** (idea 05 / ADR 25).
- Adds an MQTT broker (Mosquitto) to the stack.
- Commits spend: ZBDongle-P (~95–99,90 PLN) + 4× A1Z USED 4-pack (~109 PLN).

### Alternatives Considered

- **ZHA** — simplest for HA-only use, but telemetry stays locked inside HA; fails the infra/AI must-have.
- **NOUS E16 / ZBDongle-E (EFR32MG21)** — cheaper, multi-protocol (Thread/BLE), but EmberZNet-in-Z2M is less mature/stable than CC2652P Z-Stack.
- **deCONZ / ConBee** — vendor stack, declining momentum.
- **Network coordinators (CC2652P2 RJ45/WiFi)** — best for central placement / no USB pass-through (later Wyse 5070), pricier.
- **Tasmota / ESPHome (Wi-Fi)** — MQTT-native complement for owned Wi-Fi gear, not the chosen radio for the plugs.
- **Z-Wave, Matter/Thread** — rejected: ecosystem mismatch / not needed now.
