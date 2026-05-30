# Homelab Setup — Azure Monitor

> Runbook for enabling monitoring on the Arc-connected homelab server — CPU, memory, disk metrics, and log collection via Azure Monitor.

## Prerequisites

- [ ] Server registered in Azure Arc (see [6-azure-arc.md](6-azure-arc.md))
- [ ] Server shows status **Connected** in Azure Portal → **Azure Arc** → **Servers**
- [ ] Azure subscription with Contributor access

---

## 1. Create a Log Analytics Workspace

Log Analytics stores metrics and logs from the server. Run from your laptop with Azure PowerShell:

```powershell
New-AzOperationalInsightsWorkspace `
  -ResourceGroupName "homelab-rg" `
  -Name "homelab-law" `
  -Location "polandcentral" `
  -Sku "PerGB2018"
```

> The **PerGB2018** tier includes 5 GB/month free ingestion — plenty for a single homelab server. Costs above that are ~$2.76/GB.

---

## 2. Install the Azure Monitor Agent

The agent can be installed as an Arc extension via the Portal or PowerShell.

### Option A — From the Portal (recommended for first-time setup)

1. Go to **Azure Arc** → **Servers** → click `homelab`.
2. In the monitoring banner, click **Configure** (or go to **Monitor** → **VM Insights** → **Configure**).
3. Select the Log Analytics workspace `homelab-law`.
4. Click **Configure**. The Azure Monitor Agent extension will be pushed to the server automatically.

Wait 5–10 minutes for metrics to appear.

### Option B — Via PowerShell

```powershell
Set-AzVMExtension `
  -ResourceGroupName "homelab-rg" `
  -Location "polandcentral" `
  -VMName "homelab" `
  -Name "AzureMonitorAgent" `
  -ExtensionType "AzureMonitorLinuxAgent" `
  -Publisher "Microsoft.Azure.Monitor" `
  -TypeHandlerVersion "1.0" `
  -MachineType "HybridMachine"
```

> Use `-MachineType "HybridMachine"` for Arc-enabled servers (not regular Azure VMs).

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

- [ ] Log Analytics workspace created: `Get-AzOperationalInsightsWorkspace -ResourceGroupName "homelab-rg"`
- [ ] Azure Monitor Agent extension installed on server: `sudo azcmagent show` → lists `AzureMonitorLinuxAgent`
- [ ] Metrics visible in Portal: CPU, memory, availability charts show data
- [ ] Log Analytics receives heartbeats: `Heartbeat | where Computer == "homelab"` returns results
- [ ] VM Insights charts show performance data

---

## Next Steps

- Set up [Azure Update Management](https://learn.microsoft.com/en-us/azure/automation/update-management/overview) to schedule Ubuntu patch cycles
- Store secrets in [Azure Key Vault](https://azure.microsoft.com/en-us/products/key-vault/) for Hermes Agent and other services
- Configure [Azure Alert rules](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-new-alert-rule) for disk space, high CPU, or agent heartbeat
