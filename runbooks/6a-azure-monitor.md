# Azure Monitor Setup

> Runbook for enabling monitoring on Arc-connected servers — CPU, memory, disk metrics, and log collection via Azure Monitor. The full monitoring stack (AMA extension, DCR, DCR associations) is deployed via Bicep. Ansible handles only Arc enrollment.

## Servers

| Server | OS | Arc Status | AMA Status |
|---|---|---|---|
| `homelab` (physical) | Ubuntu 26.04 LTS | ✅ Connected | ❌ Unsupported OS — blocked upstream ([#2173](https://github.com/Azure/azure-linux-extensions/issues/2173)) |
| `cloudlab` (Contabo VPS) | Ubuntu 24.04 LTS | ✅ Connected | ✅ Installed via Bicep |

## Prerequisites

- [x] Target server registered in Azure Arc (see [6-azure-arc.md](6-azure-arc.md))
- [x] Server shows status **Connected** in Azure Portal → **Azure Arc** → **Servers**
- [x] Azure subscription with Contributor access

---

## Execution Order

Everything after Arc enrollment is a single Bicep deployment:

| Step | Tool | What |
|---|---|---|
| 1. Arc enrollment | Ansible (`azure_arc` role) | Registers server in Azure Arc |
| 2. Deploy monitoring | Bicep (`Deploy-HomelabAzResources.ps1`) | AMA extension + DCR + DCR associations |

Bicep deploys the AMA extension on the Arc server, the Data Collection Rule with `\VmInsights\DetailedMetrics`, and the DCR-to-machine association — all in one `az deployment group create` call.

---

## 1. Deploy Monitoring Stack with Bicep

The monitoring stack is defined as **Bicep + PowerShell** in [`bicep/`](../bicep/).

| File | Purpose |
|---|---|
| `main.bicep` | AMA extensions, Log Analytics workspace, Data Collection Rule, DCR associations |
| `Deploy-HomelabAzResources.ps1` | Deploys the Bicep template (parameterless) |

### What `main.bicep` creates

- **Azure Monitor Agent extensions** — `AzureMonitorLinuxAgent` on each Arc server
- **Log Analytics workspace** (`homelab-law`) — PerGB2018 tier (5 GB/month free)
- **Data Collection Rule** (`homelab-vm-dcr`) — `\VmInsights\DetailedMetrics` meta-counter every 60s → LAW
- **DCR Associations** — one per Arc server (`homelab`, `cloudlab`), linking each to the shared DCR
- **Key Vault** (`homelab-{suffix}-kv`) — RBAC-only, stores secrets (SSH keys, etc.)

### Deploy

```powershell
.\bicep\Deploy-HomelabAzResources.ps1
```

> The Bicep deployment is **incremental** — re-running it on an already-deployed resource group only adds or updates resources.

> **PerGB2018** tier includes 5 GB/month free ingestion — plenty for a two-server setup. Costs above that are ~$2.76/GB.

---

## 2. Verify

### In the Portal

Go to **Azure Arc** → **Servers** → your server → **Monitor**. You should see:

- CPU Utilization %
- Memory utilization %
- Availability

If charts show "No metrics detected", wait a few more minutes and refresh.

### On the server

Check that the Azure Monitor Agent extension is installed:

```bash
ssh labadmin@cloudlab
sudo azcmagent show
```

Look for `Extensions:` in the output — you should see `AzureMonitorLinuxAgent` listed.

### Via PowerShell

```powershell
Get-AzConnectedMachineExtension -ResourceGroupName homelab-rg -MachineName "cloudlab"
```

### View and Query Logs

1. Go to **Log Analytics workspaces** → `homelab-law` → **Logs**.
2. Try a simple query:

```kusto
Heartbeat
| where Computer == "cloudlab"
| project TimeGenerated, Computer, OSType, Version
| take 10
```

This confirms the server is heartbeating to Log Analytics.

---

## 3. Known Limitations

- **Ubuntu 26.04 not supported**: AMA v1.40.3 and v1.41.0 both fail with `Unsupported operating system: ubuntu 26.04` (exit code 51). The physical homelab (Ubuntu 26.04) cannot receive the AMA extension until Microsoft adds support.
  - Tracked: [Azure/azure-linux-extensions#2173](https://github.com/Azure/azure-linux-extensions/issues/2173)
  - Root cause: Ubuntu 26.04 ships Python 3.14 which removed `crypt`/`imp` modules, breaking extensions that depend on older Python versions.
- The `cloudlab` VPS runs Ubuntu 24.04 LTS and is **fully supported** — no issues expected.

---

## 4. Verification Checklist

- [x] Log Analytics workspace created
- [x] DCR created
- [ ] DCR association exists for each target server
- [ ] Azure Monitor Agent extension installed (`azcmagent show` or `Get-AzConnectedMachineExtension`)
- [ ] Metrics visible in Portal: CPU, memory, availability charts show data
- [ ] Log Analytics receives heartbeats: `Heartbeat | where Computer == "<server>"` returns results
- [ ] VM Insights charts show performance data (optional)

---

## Next Steps

- Configure [Azure Alert rules](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-new-alert-rule) for disk space, high CPU, or agent heartbeat
- Once Microsoft adds Ubuntu 26.04 support, re-attempt AMA on the physical `homelab` server
