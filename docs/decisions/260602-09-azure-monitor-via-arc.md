# Azure Monitor via Arc for Homelab Monitoring

**Date:** 2026-06-02  
**Status:** Deferred

---

## Context

The homelab server (Lenovo ThinkCentre M910q, Ubuntu Server) was registered in
Azure Arc ([ADR 260524](260524-hybrid-cloud-azure-arc.md)), making it visible in
the Azure Portal alongside other Azure resources. The next step was to enable
basic monitoring — CPU, memory, and disk metrics — without standing up a
separate monitoring stack.

### Constraints

- Server runs on-premises behind CGNAT, reachable only via Cloudflare Tunnel
- Ubuntu **26.04** LTS (released April 2026) — newer than most Azure extensions
  support at time of implementation
- Budget: free tier preferred; homelab is a single-server setup
- IaC preference: define infrastructure in Bicep where possible

## Decision

Use **Azure Monitor** via the Arc-connected server with the following stack:

| Component | Choice | Detail |
|---|---|---|
| Log store | Log Analytics workspace (`homelab-law`) | `PerGB2018` tier (5 GB/month free) |
| Data collection | Azure Monitor Agent extension | `AzureMonitorLinuxAgent` on Arc server |
| Routing | Data Collection Rule (`homelab-vm-dcr`) | CPU, memory, disk perf counters @ 60s, sent to LAW |
| Delivery | Bicep + PowerShell | `main.bicep` for LAW + DCR, separate script for AMA |
| IaC location | `runbooks/AzureResources/` | Collocated with deployment scripts |

The AMA extension is **not deployed via Bicep** — the publisher/type combination
is unavailable in `polandcentral` through the HybridCompute resource provider.
It is installed separately via `New-AzConnectedMachineExtension`.

## Consequences

### Positive

- **Single pane of glass** — server metrics alongside other Azure resources
- **Free tier sufficient** — 5 GB/month free ingestion covers a single server
- **IaC-ready** — Bicep + deploy script in repo for repeatable setup
- **Arc leverage** — no extra agents for identity/auth; uses the Arc server's
  managed identity
- **Extensible** — DCR can be updated to collect additional metrics or logs
  without reinstalling the agent

### Negative

- **Ubuntu 26.04 not supported** — AMA v1.40.3 and v1.41.0 both fail with
  `Unsupported operating system: ubuntu 26.04` (exit code 51). Tracked upstream:
  [Azure/azure-linux-extensions#2173](https://github.com/Azure/azure-linux-extensions/issues/2173)
  (Microsoft ICM #807185069, no fix yet)
- **Bicep limitation** — the AMA extension cannot be deployed via Bicep in
  `polandcentral`; requires a separate PowerShell step
- **Arc agent bug** — extd service (`gc_linux_service` v1.64.03414.1079) has a
  memory corruption crash (`double free or corruption`) triggered on restart;
  may require manual service restart to kick stuck extension deployments
- **OSS ecosystem miss** — if Prometheus/Grafana were already in use, a unified
  stack might be simpler than Azure-only monitoring

### Alternatives Considered

- **Prometheus + Grafana** — full OSS monitoring stack. Would require deploying
  and maintaining additional containers on the homelab. More flexible but adds
  operational overhead for a single-server setup. Consider if a Grafana dashboard
  is needed for non-Azure services later.
- **Netdata** — lightweight, rich metrics out of the box. Excellent for a single
  server but doesn't integrate with Azure Portal. Consider as a complementary
  tool if detailed real-time metrics are needed.
- **cockpit** — built into Ubuntu, zero setup. Good for quick checks but no
  alerting, no history, no cloud integration.
