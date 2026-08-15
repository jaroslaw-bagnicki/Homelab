# Homelab Monitoring & Observability Strategy — Two-Tier Model (Azure Monitor via Arc + Local Netdata Stack)

**Date:** 2026-08-15  
**Status:** Accepted

---

## Context

The homelab monitoring posture drifted as the node fleet grew. The record holds several overlapping and partly contradictory decisions:

- **ADR 09** established **Azure Monitor via Arc** as the homelab monitoring path — Log Analytics `homelab-law`, AMA extension, `\VmInsights\DetailedMetrics` DCR. Today it is **live on `cloudlab` only**: the M910q runs Ubuntu 26.04, which AMA does not support (upstream [#2173](https://github.com/Azure/azure-linux-extensions/issues/2173)), and it is not yet Arc-enrolled (issue #74 plans the 24.04 refresh to unblock this).
- **ADR 22** extends Arc to the future k3s cluster, adding Azure Monitor **Container Insights** as a cluster-level data source.
- **ADR 24** explicitly **excludes the Edge Wyse 3040** from Arc/observability agents (2 GB/8 GB soldered, "zero headroom").
- **ADR 25** (Home Assistant on the Wyse 5070) and **ADR 26** (Zigbee energy monitoring) both presuppose a **local OSS stack on the M910q** — Netdata + Fluent Bit, and Prometheus → Grafana — a "M910q observability stack" that was **never decided or stood up**.
- The **Edge** and **Home Assistant** nodes will **never be Arc-enrolled**, so Azure Monitor alone can structurally never cover the full fleet. The NAS ML110 is storage-only (ADR 23) and not an Arc candidate either.

Net result: two sinks (Azure Monitor, and an undefined local stack) with no governing decision, and the primary homelab server itself has **no working monitoring** today. Reconciliation tracked in [issue #75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75).

## Decision

Adopt a **two-tier layered monitoring model**:

- **Tier A — Azure Monitor via Arc (management plane).** AMA → Log Analytics (`homelab-law`) on **Arc-enrolled nodes only**: the M910q (after the #74 24.04 refresh), `cloudlab` (already live), and the k3s cluster via **Container Insights** (ADR 22). Free-tier surface: portal health/compliance, policy, heartbeat, KQL.
- **Tier B — Local real-time plane (every node, Arc or not).** **Netdata agent per node → Netdata Parent → Prometheus → Grafana**; **Fluent Bit → Loki** for logs (ADR 25). The AI agent reads read-only analytics via the **Prometheus API** (ADR 26). Covers the Edge, Home Assistant, NAS, Cloudlab, and future LLM node.

### Boundary rule

- **Arc = management plane only.** Tier A is for portal/policy/compliance visibility on Arc-enrolled surfaces.
- **Per-node real-time metrics come from Netdata on all nodes** (Tier B) — never a gap on non-Arc devices.
- The **Netdata Parent + Prometheus/Grafana/Loki run as k3s workloads on the M910q** after the ADR 22 migration; until then Netdata children run standalone (local `dbengine` + alarms). The agent-side specifics are owned by [ADR 28](28-netdata-adoption.md).

## Consequences

- **Two sinks to run** — Azure Monitor (Tier A) and the local Netdata/Prometheus/Grafana stack (Tier B). Tier A stays within the LAW free tier; Tier B is self-hosted on the M910q.
- **Single Grafana pane** for every node's real-time metrics; **non-Arc nodes fully covered** (Edge, HA, NAS) where Azure could never reach.
- **ADR 09 is amended in place** — scoped to Tier A (management plane); its "no separate monitoring stack" framing is superseded by this strategy.
- **Container Insights (ADR 22)** is now defined as the Tier A cluster extension, not a replacement for the local stack.
- **ADR 26's independence requirement** (monitoring survives Home Assistant restarts) is satisfied: the Tier B plane lives on the M910q k3s, not the HA node.
- **New operational overhead** — a Netdata agent per node and a central plane to maintain; minimal-agent profiles needed on constrained hardware (ADR 28).
- **Two dashboards to learn** — Azure Portal (management) and Grafana (operations). Grafana is the day-to-day surface.

### Alternatives Considered

- **Azure Monitor as the sole stack** — a single sink, but structurally cannot cover Edge/HA/NAS (never Arc-enrolled), no real-time pane, and portal-centric. Rejected.
- **Pure local OSS, no Azure** — simpler, one stack, but loses the Arc management-plane benefits (policy, compliance, portal, heartbeat) that ADR 04/09 bought with zero cost. Rejected.
- **Per-node one-off agents (cockpit/htop) with no central aggregation** — no cross-node view, no history, no alerting. Rejected.

---

## References

- [ADR 04](04-hybrid-cloud-azure-arc.md) — Hybrid Cloud Strategy (Arc management concept)
- [ADR 09](09-azure-monitor-via-arc.md) — Azure Monitor via Arc (**amended — Tier A only**)
- [ADR 22](22-k3s-arc-homelab.md) — k3s + Arc (Container Insights = Tier A cluster extension)
- [ADR 24](24-edge-ingress-appliance.md) — Edge Wyse 3040 (amended — minimal Netdata agent)
- [ADR 25](25-home-assistant-thin-client.md) — HA node (Netdata + Fluent Bit → Tier B plane)
- [ADR 26](26-zigbee-energy-monitoring.md) — Zigbee power monitoring (Prometheus → Grafana path)
- [ADR 28](28-netdata-adoption.md) — Netdata adoption (agent rollout specifics)
- [Research 17](../research/17-arc-vm-insights-setup.md) · [Research 26](../research/26-home-assistant-thin-client.md) · [Research 27](../research/27-zigbee-energy-monitoring.md)
- [Issue #75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) — monitoring reconciliation
