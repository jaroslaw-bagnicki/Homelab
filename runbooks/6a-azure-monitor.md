# Azure Monitor Setup

> Runbook for enabling monitoring on Arc-connected servers — CPU, memory, disk metrics, and log collection via Azure Monitor. Uses a shared Log Analytics workspace + Data Collection Rule; each Arc server gets its own DCR association and AMA extension.

## Servers

| Server | OS | Arc Status | AMA Status |
|---|---|---|---|
| `homelab` (physical) | Ubuntu 26.04 LTS | ✅ Connected | ❌ Unsupported OS — blocked upstream ([#2173](https://github.com/Azure/azure-linux-extensions/issues/2173)) |
| `cloudlab` (Contabo VPS) | Ubuntu 24.04 LTS | ✅ Connected | ⬜ Not yet installed |

## Prerequisites

- [x] Target server registered in Azure Arc (see [6-azure-arc.md](6-azure-arc.md))
- [x] Server shows status **Connected** in Azure Portal → **Azure Arc** → **Servers**
- [x] Azure subscription with Contributor access
- [x] Dev container (or control machine) with `Az.ConnectedMachine` PowerShell module

---

## Execution Order

There are two independent steps — **Bicep** (DCR association) and **Ansible** (AMA install). The order matters for how quickly metrics appear, but both orders work:

| Order | Flow | When metrics appear |
|---|---|---|
| **New VPS enrollment** (natural) | Ansible installs AMA first → Bicep creates DCR association later | A few minutes after Bicep runs (AMA polls for new DCRs every few minutes) |
| **Retroactive setup** (existing Arc server) | Bicep creates DCR association first → Ansible installs AMA | Immediately after AMA install (DCR already exists, agent picks it up on first poll) |

During VPS enrollment via `playbook.yml`, Ansible runs `azure_arc` → `azure_monitor` in sequence, so AMA gets installed right after Arc enrolment. The DCR association is created separately when you deploy the Bicep — the AMA agent will discover it on its next polling cycle.

---

## 1. Deploy Shared Infrastructure with Bicep

The monitoring stack is defined as **Bicep + PowerShell** in [`runbooks/AzureResources/`](AzureResources/).

| File | Purpose |
|---|---|
| `main.bicep` | Log Analytics workspace, Data Collection Rule (DCR), and DCR associations |
| `Deploy-HomelabAzResources.ps1` | Deploys the Bicep template (parameterless) |

### What `main.bicep` creates

- **Log Analytics workspace** (`homelab-law`) — PerGB2018 tier (5 GB/month free)
- **Data Collection Rule** (`homelab-vm-dcr`) — CPU, memory, disk perf counters every 60s → LAW
- **DCR Associations** — one per Arc server (`homelab`, `cloudlab`), linking each to the shared DCR
- **Key Vault** (`homelab-{suffix}-kv`) — RBAC-only, stores secrets (SSH keys, etc.)

### Deploy

```powershell
.\runbooks\AzureResources\Deploy-HomelabAzResources.ps1
```

> The Bicep deployment is **incremental** — re-running it on an already-deployed resource group only adds missing resources (e.g. a new DCR association for a newly enrolled server).

> **PerGB2018** tier includes 5 GB/month free ingestion — plenty for a two-server setup. Costs above that are ~$2.76/GB.

---

## 2. Install the Azure Monitor Agent via Ansible

The AMA extension (`AzureMonitorLinuxAgent`) is **not available** in `polandcentral` through the HybridCompute resource provider, so it cannot be deployed via Bicep. The **`azure_monitor` Ansible role** handles this by delegating `New-AzConnectedMachineExtension` to the control machine (dev container).

### Add a new server to the playbook

If the target is not already in `playbook.yml`, add the role:

```yaml
roles:
    - azure_monitor
```

### Run the playbook

```powershell
ansible-playbook ansible/playbooks/playbook.yml --tags azure_monitor
```

Or run the full playbook (idempotent — skips if AMA is already installed):

```powershell
ansible-playbook ansible/playbooks/playbook.yml
```

### What the role does

1. Checks if `AzureMonitorAgent` extension is already installed on the Arc server.
2. If not, runs `New-AzConnectedMachineExtension` from the control machine (delegated localhost).
3. Prints the installation result.

### Manual fallback

If Ansible is not available, install directly via PowerShell:

```powershell
New-AzConnectedMachineExtension `
  -ResourceGroupName homelab-rg `
  -Location polandcentral `
  -MachineName "cloudlab" `
  -Name AzureMonitorAgent `
  -ExtensionType AzureMonitorLinuxAgent `
  -Publisher Microsoft.Azure.Monitor `
  -TypeHandlerVersion "1.41"
```

> **Note**: `Set-AzVMExtension -MachineType HybridMachine` does **not** work — the `-MachineType` parameter is not available in the current Az module. Use `Az.ConnectedMachine` instead.

---

## 3. Enable VM Insights (Optional)

VM Insights provides pre-built charts for CPU, memory, disk, and network.

1. In the Portal, go to **Azure Arc** → **Servers** → your server → **Monitor** → **VM Insights**.
2. Click **Enable**.
3. Select `homelab-law` as the Log Analytics workspace.
4. Click **Configure**.

After a few minutes, the **Performance** tab will show live CPU, memory, and disk charts.

---

## 4. Verify

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

## 5. Known Limitations

- **Ubuntu 26.04 not supported**: AMA v1.40.3 and v1.41.0 both fail with `Unsupported operating system: ubuntu 26.04` (exit code 51). The physical homelab (Ubuntu 26.04) cannot receive the AMA extension until Microsoft adds support.
  - Tracked: [Azure/azure-linux-extensions#2173](https://github.com/Azure/azure-linux-extensions/issues/2173)
  - Root cause: Ubuntu 26.04 ships Python 3.14 which removed `crypt`/`imp` modules, breaking extensions that depend on older Python versions.
- The `cloudlab` VPS runs Ubuntu 24.04 LTS and is **fully supported** — no issues expected.

---

## 6. Verification Checklist

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
