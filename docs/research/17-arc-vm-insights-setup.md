---
source: https://learn.microsoft.com/en-us/azure/azure-arc/servers/learn/tutorial-enable-vm-insights
model: DeepSeek V4 Pro
date: 2026-06-21
---

# 17 — Azure Arc VM Insights: Why the Monitor Blade Shows "No Data"

## Topic

Investigation into why the `cloudlab` Arc-enabled server shows "No Data" in the Azure Portal's Monitor/Insights blade despite the Azure Monitor Agent (AMA) being installed, the Data Collection Rule (DCR) being associated, and performance data flowing to the Log Analytics workspace's `InsightsMetrics` table.

---

## Key Findings

### 1. The data pipeline is healthy — data IS being collected

- **AMA extension** v1.41.2 installed on `cloudlab` — `ProvisioningState: Succeeded`
- **DCR** `homelab-vm-dcr` configured with 3 performance counters (CPU, Memory, Disk) @ 60s → `Microsoft-InsightsMetrics` stream → `homelab-law` workspace
- **DCR association** `cloudlab-vm-dcr-association` links `cloudlab` to the DCR — scoped correctly to the HybridCompute machine
- **InsightsMetrics table** in LAW contains data with `_ResourceId` pointing to `cloudlab` — confirmed in the portal and by the user's own log query

The collection pipeline works. The problem is not data collection — it's that the portal's monitoring experience doesn't know how to display the collected data.

### 2. Bicep deploys infrastructure, but the portal onboarding is a separate step

The `main.bicep` template deploys:
- Log Analytics workspace (`homelab-law`)
- Data Collection Rule (`homelab-vm-dcr`) with perf counters
- DCR associations for `homelab` and `cloudlab`
- `VMInsights(homelab-law)` solution (intended but not found in resource group — API version may be invalid)

However, the [official Azure Arc VM Insights tutorial](https://learn.microsoft.com/en-us/azure/azure-arc/servers/learn/tutorial-enable-vm-insights) explicitly requires going through the **portal's "Configure" flow** to complete VM Insights enablement:

> *"If enhanced monitoring wasn't enabled, several performance charts show no data and a message appears offering to enable it. Select **Configure** to open the Configure monitor page."*

The portal onboarding orchestrates several things that the Bicep template does not:
1. Creates a VM Insights-specific monitoring pipeline that the portal experience understands
2. Enables the **new OpenTelemetry-based metrics collection** (the "metrics-based visualizations" preview)
3. Wires the portal's Insights blade to the correct DCR and data sources

### 3. Two monitoring experiences — classic (log-based) and new (metrics-based)

The portal offers two experiences, selectable via a dropdown at the top of the Insights page:

| Experience | Data source | What charts show |
|---|---|---|
| **Metrics-based visualizations (Preview)** | OpenTelemetry → Azure Monitor Metrics | CPU, Memory, Disk, Network + Service/Resource Health |
| **Log-based visualizations (Classic)** | `InsightsMetrics` table in LAW | CPU, Memory, Disk perf counters + Map (Dependency Agent) |

The user's screenshot shows the **log-based (classic)** experience with "No Data" and a banner: **"Upgrade to the new monitoring experience"**. This means:
- The classic experience hasn't been wired up — the portal doesn't know which DCR/workspace to read from
- The new metrics-based experience hasn't been configured at all

### 4. The VMInsights solution may not be deployed correctly

`Get-AzResource` returns 9 resources in `homelab-rg` — none of type `Microsoft.OperationsManagement/solutions`. The Bicep deploys `VMInsights(homelab-law)` using API version `2021-06-01-preview`, which may be invalid or rejected by the RP. This solution is required for the classic log-based VM Insights experience (it adds the Map feature and pre-built workbook queries).

### 5. DCR scope — correct but the console experience is misleading

The DCR association is scoped to the machine (visible in the `Id` field: `.../machines/cloudlab/providers/Microsoft.Insights/dataCollectionRuleAssociations/cloudlab-vm-dcr-association`). This is correct for Arc servers.

The "No Data" in the portal is **not** caused by a missing or misconfigured DCR — it's caused by the VM Insights enablement not being completed through the portal.

### 6. Alternative: Query data directly via Workbooks or Logs

Even without the portal's VM Insights charts, the collected data is fully usable:
- **Logs**: Query `InsightsMetrics` table in `homelab-law` (already working)
- **Workbooks**: Create custom workbooks reading from `InsightsMetrics`
- **Alerts**: Create metric alerts based on Log Analytics queries
- **Dashboards**: Pin custom charts to Azure dashboards

---

## Recommendations

### Immediate fix

1. In the Azure Portal, navigate to **Azure Arc → Machines → cloudlab → Monitoring → Insights**
2. Click the **Configure** button on the banner ("Upgrade to the new monitoring experience")
3. Follow the wizard — select the existing `homelab-law` workspace
4. Click **Review + Enable**, then **Enable**
5. Wait a few minutes for charts to populate

This is the documented, supported path from the [official tutorial](https://learn.microsoft.com/en-us/azure/azure-arc/servers/learn/tutorial-enable-vm-insights).

### If the portal "Configure" button doesn't appear

If the portal shows the classic view without a Configure banner, try:
1. The **"Monitoring configuration"** button in the toolbar at the top of the Insights page
2. Or navigate to **Azure Arc → Machines → cloudlab → Monitoring → Insights → Enable** (may appear as a separate button)

### Long-term: Fix the Bicep template

Once the portal onboarding confirms everything works, investigate:
- Why `VMInsights(homelab-law)` doesn't appear in the resource group (check API version `2021-06-01-preview` — may need to use a stable version or move to a different API surface)
- Whether the DCR data sources need to be expanded to match VM Insights' expected counter set (CPU, Memory, Disk, **Network**)
- The portal onboarding creates its own managed DCR — whether to keep the custom DCR or migrate to the portal-managed one

### DCR counter expansion

VM Insights expects more counters than the 3 currently configured. Consider expanding to:

```bicep
counterSpecifiers: [
  '\\Processor\\% Processor Time'
  '\\Processor\\% Idle Time'
  '\\Processor\\% Privileged Time'
  '\\Processor\\% User Time'
  '\\Memory\\% Used Memory'
  '\\Memory\\% Available Memory'
  '\\Memory\\Used MBytes'
  '\\Memory\\Available MBytes'
  '\\Disk\\% Used Space'
  '\\Disk\\Read Bytes/sec'
  '\\Disk\\Write Bytes/sec'
  '\\Disk\\Reads/sec'
  '\\Disk\\Writes/sec'
  '\\Network\\Total Bytes'
  '\\Network\\Bytes Sent/sec'
  '\\Network\\Bytes Received/sec'
]
```

This ensures VM Insights charts for CPU breakdown, disk IO, and network have data to display.

---

## References

- [Tutorial: Monitor a hybrid machine with VM Insights](https://learn.microsoft.com/en-us/azure/azure-arc/servers/learn/tutorial-enable-vm-insights)
- [Enable VM Insights for hybrid machines](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-enable-hybrid)
- [Cloud Adoption Framework: Arc server monitoring](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/hybrid/arc-enabled-servers/eslz-management-and-monitoring-arc-server)
- [ADR 09: Azure Monitor via Arc](https://github.com/jaroslaw-bagnicki/Homelab/blob/main/docs/decisions/260602-09-azure-monitor-via-arc.md)
- [Runbook 6a: Azure Monitor Setup](https://github.com/jaroslaw-bagnicki/Homelab/blob/main/runbooks/6a-azure-monitor.md)
