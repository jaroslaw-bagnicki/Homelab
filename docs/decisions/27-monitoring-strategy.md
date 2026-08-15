# Homelab Monitoring & Observability Strategy — Two-Tier Model (Azure Monitor via Arc + Netdata on Every Node)

**Date:** 2026-08-15  
**Status:** Accepted

---

## Context

The homelab monitoring posture drifted as the node fleet grew. The record holds several overlapping and partly contradictory decisions:

- **ADR 09** established **Azure Monitor via Arc** as the homelab monitoring path — Log Analytics `homelab-law`, AMA extension, `\VmInsights\DetailedMetrics` DCR. Today it is **live on `cloudlab` only**: the M910q runs Ubuntu 26.04, which AMA does not support (upstream [#2173](https://github.com/Azure/azure-linux-extensions/issues/2173)), and it is not yet Arc-enrolled (issue #74 plans the 24.04 refresh to unblock this).
- **ADR 22** extends Arc to the future k3s cluster, adding Azure Monitor **Container Insights** as a cluster-level data source.
- **ADR 24** explicitly **excludes the Edge Wyse 3040** from Arc/observability agents (2 GB/8 GB soldered, "zero headroom").
- **ADR 25** (Home Assistant on the Wyse 5070) and **ADR 26** (Zigbee energy monitoring) both presuppose a **local OSS stack on the M910q** — Netdata + Fluent Bit, and Prometheus → Grafana — a referenced-but-undecided "M910q observability stack" that was **never decided or stood up**.
- New nodes are arriving — the Edge Wyse 3040 now, the Home Assistant Wyse 5070 next, the LLM server later — and each needs real-time, per-node monitoring without Arc. ADR 09 already considered **Netdata** as a complementary tool but never adopted it.
- The **Edge** and **Home Assistant** nodes will **never be Arc-enrolled**, so Azure Monitor alone can structurally never cover the full fleet. The NAS ML110 is storage-only (ADR 23) and not an Arc candidate either.

Net result: two sinks (Azure Monitor, and a referenced-but-undecided local stack) with no governing decision, and the primary homelab server itself has **no working monitoring** today. Reconciliation tracked in [issue #75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75).

## Decision

Adopt a **two-tier layered monitoring model**:

### Tier A — Azure Monitor via Arc (management plane)

AMA → Log Analytics (`homelab-law`) on **Arc-enrolled nodes only**: the M910q (after the #74 24.04 refresh), `cloudlab` (already live), and the k3s cluster via **Container Insights** (ADR 22). Free-tier surface: portal health/compliance, policy, heartbeat, KQL.

### Tier B — Netdata on every node (local real-time plane)

**Netdata agent per node → Netdata Parent** (k3s workload on the M910q) → **Netdata dashboard + alarms**. Covers the Edge, Home Assistant, NAS, Cloudlab, and future LLM node — Arc or not.

- **Agent on all nodes** — M910q, ML110 OMV NAS, Edge Wyse 3040, HA Proxmox host (Wyse 5070), `cloudlab` VPS, future LLM node: a uniform agent across Ubuntu, Debian, OMV, Proxmox, and (trial pending) Alpine.
- **Parent placement** — Netdata Parent runs as a **k3s workload on the M910q** after the ADR 22 migration; until then children run **standalone** (local `dbengine` + alarms) and re-point to the parent when it lands.
- **Edge Wyse 3040 — minimal agent (explicit ADR 24 override).** Smallest practical footprint; Alpine compatibility validated during the Debian-vs-Alpine on-device trial.
- **Metrics-only scope.** Provisioned via a new Ansible `netdata` role (ADR 10).
- **Extensions of Tier B (not adopted — no ADR yet):** **Grafana, Prometheus, Fluent Bit, Loki.** Netdata's Prometheus-compatible export is the future integration point for a dashboard/analytics (and log) extension; **ADR 26's power path** (Z2M → `mqtt2prometheus` → Prometheus → Grafana) is the only committed Prometheus/Grafana usage today. These extensions are adopted only via their own future ADRs.

### Boundary rule

- **Arc = management plane only.** Tier A is for portal/policy/compliance visibility on Arc-enrolled surfaces.
- **Per-node real-time metrics come from Netdata on all nodes** (Tier B) — never a gap on non-Arc devices.
- **Tier B extensions** (Grafana/Prometheus/Fluent Bit/Loki) are adopted only through their own future ADRs, not this one.

## Consequences

- **Two planes to run** — Azure Monitor (Tier A) and the local Netdata plane (Tier B). Tier A stays within the LAW free tier; Tier B is self-hosted on the M910q.
- **Single Netdata Parent pane** for every node's real-time metrics; **non-Arc nodes fully covered** (Edge, HA, NAS) where Azure could never reach.
- **One agent everywhere** — a uniform monitoring tool across heterogeneous nodes; auto-discovers containers, VMs/LXC (Proxmox), and services with rich out-of-the-box metrics.
- **Standalone-first, parent-later** — every child is useful immediately (local dashboard + alarms) before the k3s central plane exists; re-pointing to the parent is a config change, not a reinstall.
- **ADR 09 is amended in place** — scoped to Tier A (management plane); its "no separate monitoring stack" framing is superseded by this strategy.
- **Container Insights (ADR 22)** is now defined as the Tier A cluster extension, not a replacement for the local plane.
- **ADR 26's independence requirement** (monitoring survives Home Assistant restarts) is satisfied: the Tier B plane lives on the M910q k3s, not the HA node.
- **New operational overhead** — a Netdata agent per node (~100–150 MB default; minimal profile ~60–100 MB on the constrained Edge) and a central plane to maintain.
- **Two dashboards to learn** — Azure Portal (management) and the Netdata dashboard (operations); a Grafana surface appears only if the Tier B extension is adopted.

### Alternatives Considered

- **Azure Monitor as the sole stack** — a single sink, but structurally cannot cover Edge/HA/NAS (never Arc-enrolled), no real-time pane, and portal-centric. Rejected.
- **Pure local OSS, no Azure** — simpler, one stack, but loses the Arc management-plane benefits (policy, compliance, portal, heartbeat) that ADR 04/09 bought with zero cost. Rejected.
- **Per-node one-off agents (cockpit/htop) with no central aggregation** — no cross-node view, no history, no alerting. Rejected.
- **Prometheus node_exporter as the local agent** — lighter than Netdata but no dashboard, no alarms, no auto-discovery, and useless standalone (needs a central Prometheus from day one). Rejected in favor of Netdata.

---

## References

- [ADR 04](04-hybrid-cloud-azure-arc.md) — Hybrid Cloud Strategy (Arc management concept)
- [ADR 09](09-azure-monitor-via-arc.md) — Azure Monitor via Arc (**amended — Tier A only**)
- [ADR 10](10-ansible-host-config.md) — Ansible host configuration (`netdata` role)
- [ADR 22](22-k3s-arc-homelab.md) — k3s + Arc (Container Insights = Tier A cluster extension)
- [ADR 24](24-edge-ingress-appliance.md) — Edge Wyse 3040 (amended — minimal Netdata agent)
- [ADR 25](25-home-assistant-thin-client.md) — HA node (Netdata → Tier B plane)
- [ADR 26](26-zigbee-energy-monitoring.md) — Zigbee power monitoring (Prometheus → Grafana path, only committed Prometheus/Grafana usage)
- [Research 17](../research/17-arc-vm-insights-setup.md) · [Research 25](../research/25-edge-ingress-sbc.md) · [Research 26](../research/26-home-assistant-thin-client.md) · [Research 27](../research/27-zigbee-energy-monitoring.md)
- [Issue #75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) — monitoring reconciliation
