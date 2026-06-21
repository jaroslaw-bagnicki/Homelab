---
source: https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring
model: DeepSeek V4 Pro
date: 2026-06-21
---

# 17 — Azure Arc VM Insights: Why the Monitor Blade Shows "No Data"

## Topic

Investigation into why the `cloudlab` Arc-enabled server shows "No Data" in the Azure Portal's Monitor/Insights blade despite the Azure Monitor Agent (AMA) being installed, the Data Collection Rule (DCR) being associated, and performance data flowing to the Log Analytics workspace's `InsightsMetrics` table.

---

## Key Findings

### 1. The data pipeline was healthy — data WAS being collected

- **AMA extension** v1.41.2 installed on `cloudlab` — `ProvisioningState: Succeeded`
- **DCR** `homelab-vm-dcr` configured with 3 individual Linux perf counters (CPU, Memory, Disk) @ 60s
- **DCR association** `cloudlab-vm-dcr-association` linked `cloudlab` to the DCR — scoped correctly
- **InsightsMetrics table** in LAW contained data with `_ResourceId` pointing to `cloudlab`

The collection pipeline worked. The problem was that the data didn't match what VM Insights expects.

### 2. Root cause: wrong counter specifier in the DCR

The DCR used individual Linux performance counters:

```bicep
counterSpecifiers: [
  '\\Processor\\% Processor Time'
  '\\Memory\\% Used Memory'
  '\\Disk\\% Used Space'
]
```

The [official VM enable monitoring docs](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring) specify a **VM Insights meta-counter** instead — a single token that the AMA interprets as "collect the full VM Insights standard counter set":

```bicep
counterSpecifiers: [
  '\\VmInsights\\DetailedMetrics'
]
```

`\VmInsights\DetailedMetrics` is not a real OS counter. It's a **proprietary token** that the AMA expands into the full ~15-counter VM Insights set (CPU breakdown, memory, disk IO, network) and — critically — adds the metadata tagging that the portal's VM Insights workbooks use to find and display the data.

Individual counters send raw data to `InsightsMetrics`, but without the VM Insights-specific tagging, the portal charts can't identify them as VM Insights data — hence "No Data" in the blade.

### 3. Classic vs OpenTelemetry monitoring

The portal offers two experiences:

| Experience | Data source | Maturity |
|---|---|---|
| **Metrics-based (Preview)** | OpenTelemetry → Azure Monitor Workspace | Preview, needs separate `Microsoft.Monitor/accounts` resource |
| **Log-based (Classic)** | `\VmInsights\DetailedMetrics` → `InsightsMetrics` table in LAW | GA, stable |

Classic alone is sufficient for homelab use. OTel adds near-real-time metrics (~30s vs minutes) and an extra ingestion cost — overkill for a single server.

### 4. "This DCR shouldn't be modified" — only applies to portal-managed DCRs

The docs warn against modifying VM Insights DCRs because the portal may overwrite changes. Since the homelab DCR is Bicep-managed (not portal-created), this warning doesn't apply — the DCR is fully IaC-controlled.

---

## Fix Applied

Two changes to `main.bicep` (commit `9715401`):

1. **DCR counter** — changed from 3 individual Linux counters to the single `\\VmInsights\\DetailedMetrics` meta-counter, matching the official docs

```bicep
// Before
counterSpecifiers: [
  '\\Processor\\% Processor Time'
  '\\Memory\\% Used Memory'
  '\\Disk\\% Used Space'
]

// After
counterSpecifiers: [
  '\\VmInsights\\DetailedMetrics'
]
```

After redeployment, the AMA will start sending VM Insights-tagged data to `InsightsMetrics`, and the portal's classic log-based charts should populate within minutes.

**Verified 2026-06-21**: After Bicep redeployment with the `\VmInsights\DetailedMetrics` counter, the `cloudlab` Insights page shows live CPU, Memory, and Disk charts. Classic log-based monitoring confirmed working.

---

## References

- [Enable VM monitoring with Azure Monitor Agent](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring) — the canonical DCR shape for VM Insights with AMA
- [Cloud Adoption Framework: Arc server monitoring](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/hybrid/arc-enabled-servers/eslz-management-and-monitoring-arc-server)
- [ADR 09: Azure Monitor via Arc](https://github.com/jaroslaw-bagnicki/Homelab/blob/main/docs/decisions/260602-09-azure-monitor-via-arc.md)
- [Runbook 6a: Azure Monitor Setup](https://github.com/jaroslaw-bagnicki/Homelab/blob/main/runbooks/6a-azure-monitor.md)
