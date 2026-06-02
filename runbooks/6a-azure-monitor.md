# Homelab Setup — Azure Monitor

> Runbook for enabling monitoring on the Arc-connected homelab server — CPU, memory, disk metrics, and log collection via Azure Monitor.

## Prerequisites

- [x] Server registered in Azure Arc (see [6-azure-arc.md](6-azure-arc.md))
- [x] Server shows status **Connected** in Azure Portal → **Azure Arc** → **Servers**
- [x] Azure subscription with Contributor access

---

## 1. Deploy Infrastructure with Bicep

The monitoring stack is defined as **Bicep + PowerShell** in [`runbooks/AzureResources/`](AzureResources/).

| File | Purpose |
|---|---|
| `main.bicep` | Log Analytics workspace, Data Collection Rule (DCR), and DCR association |
| `Deploy-HomelabAzResources.ps1` | Deploys the Bicep template |
| `Install-AzureMonitorAgent.ps1` | Installs the AMA extension (separate step — see below) |

### What `main.bicep` creates

- **Log Analytics workspace** (`homelab-law`) — stores metrics and logs (PerGB2018 tier)
- **Data Collection Rule** (`homelab-vm-dcr`) — collects CPU, memory, and disk performance counters every 60s, sends them to the LAW
- **DCR Association** — links the rule to the Arc-enabled server `homelab`

### Deploy

```powershell
.\runbooks\AzureResources\Deploy-HomelabAzResources.ps1
```

The `location` parameter is required (passed via the script — hardcoded to `polandcentral`).

> **PerGB2018** tier includes 5 GB/month free ingestion — plenty for a single homelab server. Costs above that are ~$2.76/GB.

---

## 2. Install the Azure Monitor Agent

The AMA extension (`AzureMonitorLinuxAgent`) is **not available** in `polandcentral` through the HybridCompute resource provider, so it cannot be deployed via Bicep. It must be installed via PowerShell using the `Az.ConnectedMachine` module.

```powershell
.\runbooks\AzureResources\Install-AzureMonitorAgent.ps1
```

This runs `New-AzConnectedMachineExtension` on the Arc server `homelab`. The extension installs the Azure Monitor Agent which forwards telemetry according to the DCR.

> **Note**: `Set-AzVMExtension -MachineType HybridMachine` does **not** work — the `-MachineType` parameter is not available in the current Az module. Use `Az.ConnectedMachine` instead.

---

## 3. Enable VM Insights (Optional)

VM Insights provides pre-built charts for CPU, memory, disk, and network.

1. In the Portal, go to **Azure Arc** → **Servers** → `homelab` → **Monitor** → **VM Insights**.
2. Click **Enable**.
3. Select `homelab-law` as the Log Analytics workspace.
4. Click **Configure**.

After a few minutes, the **Performance** tab will show live CPU, memory, and disk charts.

---

## 4. Verify

### In the Portal

Go to **Azure Arc** → **Servers** → `homelab` → **Monitor**. You should see:

- CPU Utilization %
- Memory utilization %
- Availability

If charts show "No metrics detected", wait a few more minutes and refresh.

### On the server

Check that the Azure Monitor Agent extension is installed:

```bash
ssh jarek@homelab.local
sudo azcmagent show
```

Look for `Extensions:` in the output — you should see `AzureMonitorLinuxAgent` listed.

### Via PowerShell

```powershell
Get-AzConnectedMachineExtension -ResourceGroupName "homelab-rg" -MachineName "homelab"
```

---

## 5. View and Query Logs

1. Go to **Log Analytics workspaces** → `homelab-law` → **Logs**.
2. Try a simple query:

```kusto
Heartbeat
| where Computer == "homelab"
| project TimeGenerated, Computer, OSType, Version
| take 10
```

This confirms the server is heartbeating to Log Analytics.

---

## 6. Verification Checklist

- [x] Log Analytics workspace created
- [ ] Azure Monitor Agent extension installed (`azcmagent show` or `Get-AzConnectedMachineExtension`)
- [ ] Metrics visible in Portal: CPU, memory, availability charts show data
- [ ] Log Analytics receives heartbeats: `Heartbeat | where Computer == "homelab"` returns results
- [ ] VM Insights charts show performance data

---

## Next Steps

- Set up [Azure Update Management](https://learn.microsoft.com/en-us/azure/automation/update-management/overview) to schedule Ubuntu patch cycles
- Store secrets in [Azure Key Vault](https://azure.microsoft.com/en-us/products/key-vault/) for Hermes Agent and other services
- Configure [Azure Alert rules](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-new-alert-rule) for disk space, high CPU, or agent heartbeat
