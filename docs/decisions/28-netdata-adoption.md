# Netdata Agent on Every Node — Local Real-Time Metrics

**Date:** 2026-08-15  
**Status:** Accepted

---

## Context

New nodes are arriving in the homelab — the Edge Wyse 3040 now, Home Assistant on the Wyse 5070 next, the LLM server later. Each needs real-time, per-node monitoring, and none of the constrained/new nodes is Arc-enrolled ([ADR 24](24-edge-ingress-appliance.md), [ADR 25](25-home-assistant-thin-client.md)). [ADR 27](27-monitoring-strategy.md) establishes the **Tier B local plane** (Netdata → Parent → Prometheus → Grafana) as the monitoring path for every node; this ADR owns the **agent-side** specifics.

Prior context:

- ADR 09 already considered **Netdata** as a complementary tool ("excellent for a single server… consider as a complementary tool") — it was deferred, never adopted.
- ADR 25 already specifies **Netdata + Fluent Bit on the Proxmox host** of the HA node.
- ADR 26's power-monitoring path lands in **Prometheus → Grafana**; Netdata must feed the same sink.
- ADR 24 recorded "zero headroom for future agents" on the 2 GB/8 GB Edge — an **explicit override** is needed to place a minimal agent there.

## Decision

**Run a Netdata agent on every homelab node, streaming (or feeding) into the ADR 27 Tier B central plane.**

- **Nodes:** M910q (main host + future parent), ML110 OMV NAS, Edge Wyse 3040, HA Proxmox host (Wyse 5070), `cloudlab` VPS, and the future LLM node — a uniform agent across Ubuntu, Debian, OMV, Proxmox, and (trial pending) Alpine.
- **Parent placement:** Netdata Parent + Prometheus + Grafana (+ Loki for Fluent Bit logs, ADR 25) run as **k3s workloads on the M910q** after the ADR 22 migration. Until then, children run **standalone** — local `dbengine` retention and local alarms — and are re-pointed at the parent when it lands.
- **Edge Wyse 3040 — minimal agent (explicit ADR 24 override).** Smallest practical footprint: reduced cache, capped `dbengine`, dashboard LAN-only. Alpine compatibility of the Netdata agent is validated during the Debian-vs-Alpine on-device trial; if unsupported there, the Debian baseline is used.
- **Data flow:** child → Netdata Parent (Netdata streaming) → Prometheus (scrape `/metrics` or remote-write) → Grafana; AI-agent read-only analytics via the Prometheus API (ADR 26). Fluent Bit (ADR 25) → Loki on the M910q.
- **Provisioning:** a new Ansible `netdata` role (ADR 10) installs and configures the agent per-node; `cloudlab` reaches the parent via its existing tunnel/public path.

## Consequences

- **One agent everywhere** — a single monitoring tool across heterogeneous nodes; auto-discovers containers, VMs/LXC (Proxmox), and services with rich out-of-the-box metrics.
- **Non-Arc and constrained nodes get real-time coverage** — Edge, HA, NAS — where Azure Monitor can never reach (ADR 27 boundary rule).
- **Standalone-first, parent-later** — every child is useful immediately (local dashboard + alarms) before the k3s central plane exists; re-pointing to the parent is a config change, not a reinstall.
- **Resource cost per node** — ~100–150 MB RAM for a default agent (M910q, ML110 4 GB, HA 8 GB, cloudlab all fine); Edge 3040 runs a minimal profile (~60–100 MB) and is the tightest fit — accepted as a deliberate constraint, with the Wyse 5070 fallback (ADR 24) if the ceiling is hit.
- **New agent surface on a public-facing box** — the Edge's Netdata dashboard is bound to LAN and its network path is minimized; the agent itself is an additional process on an internet-facing device.
- **Alarm philosophy** — per-node Netdata alarms stay local for now; centralized alerting (Alertmanager/Grafana) is deferred until the k3s central plane exists.

### Alternatives Considered

- **Prometheus node_exporter per node** — lighter than Netdata but delivers no dashboard, no alarms, no auto-discovery, and is useless standalone (needs the parent's Prometheus from day one). Rejected.
- **Telegraf + InfluxDB** — heavier agent and a separate TSDB; ADR 26 already commits the sink to Prometheus. Rejected.
- **Per-node cockpit (no agent, no central)** — zero central view, no history. Rejected.

---

## References

- [ADR 09](09-azure-monitor-via-arc.md) — Azure Monitor via Arc (Netdata first considered there)
- [ADR 10](10-ansible-host-config.md) — Ansible host configuration (`netdata` role)
- [ADR 22](22-k3s-arc-homelab.md) — k3s on the M910q (parent/workload home)
- [ADR 24](24-edge-ingress-appliance.md) — Edge Wyse 3040 (**amended — minimal Netdata agent**)
- [ADR 25](25-home-assistant-thin-client.md) — HA Proxmox host (Netdata + Fluent Bit)
- [ADR 26](26-zigbee-energy-monitoring.md) — Prometheus → Grafana path + AI-agent access
- [ADR 27](27-monitoring-strategy.md) — Two-tier monitoring strategy (this ADR's parent)
- [Research 25](../research/25-edge-ingress-sbc.md) · [Research 26](../research/26-home-assistant-thin-client.md) · [Research 27](../research/27-zigbee-energy-monitoring.md)
- [Issue #75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) — monitoring reconciliation
