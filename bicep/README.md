# Bicep

Infrastructure as Code for Azure resources shared across the Homelab — monitoring stack, Key Vault, and SSH keys. Deployed from the dev container via PowerShell.

## Quickstart

```powershell
.\bicep\Deploy-HomelabAzResources.ps1
```

Idempotent — safe to re-run on an already-deployed resource group. Only adds or updates resources.

## Structure

| Path | Purpose |
|---|---|
| `main.bicep` | All Azure resource definitions |
| `Deploy-HomelabAzResources.ps1` | Deploys `main.bicep` via `New-AzResourceGroupDeployment` |
| `SETUP_LOG.md` | Historical session log (2026-06-02) — initial deployment notes |

## What `main.bicep` creates

| Resource | Name | Purpose |
|---|---|---|
| Log Analytics workspace | `homelab-law` | Metric & log sink for Arc servers (PerGB2018, 5 GB/month free) |
| Data Collection Rule | `homelab-vm-dcr` | VM Insights meta-counter (`\VmInsights\DetailedMetrics`) → `InsightsMetrics` table @ 60s |
| DCR associations | `{machine}-vm-dcr-association` | One per Arc server, links each to the shared DCR |
| Azure Monitor Agent | `AzureMonitorAgent` | One AMA extension per Arc server (`AzureMonitorLinuxAgent`, auto-upgrade enabled) |
| Key Vault | `homelab-{suffix}-kv` | RBAC-only, stores SSH keys and secrets |
| SSH public key | `cloudlab-vps-key` | Azure-managed SSH key for VPS access |

## Relationship to Ansible

| Layer | Tool | Scope |
|---|---|---|
| Host provisioning | Ansible | OS hardening, Docker, Arc agent binary |
| Cloud-side resources | Bicep | Monitoring, extensions, DCRs, Key Vault |
| Arc enrollment | Manual (post-Ansible) | `azcmagent connect` with service principal |

Ansible runs first (on the bare host), then Bicep deploys cloud resources. The Arc agent must be enrolled in Azure before Bicep can deploy the AMA extension.

## Deployment notes

- **Region**: `polandcentral` (Warsaw — closest Azure region)
- **Resource group**: `homelab-rg`
- **Incremental mode**: re-running only adds/updates, never deletes
- The AMA extension (`AzureMonitorLinuxAgent`) is deployed via `Microsoft.HybridCompute/machines/extensions` — this requires the Arc server to already be enrolled
- `\VmInsights\DetailedMetrics` is a VM Insights meta-counter that the agent expands into the full perf counter set (CPU, Memory, Disk, Network)

## Known limitations

- **Ubuntu 26.04 not supported**: AMA fails on the physical `homelab` server (Ubuntu 26.04) with `Unsupported operating system` (exit code 51). Tracked upstream: [Azure/azure-linux-extensions#2173](https://github.com/Azure/azure-linux-extensions/issues/2173)
- `cloudlab` (Ubuntu 24.04) is fully supported — no issues expected

---

**References:**
- [Runbook 6a: Azure Monitor Setup](../runbooks/6a-azure-monitor.md)
- [ADR 09: Azure Monitor via Arc](../docs/decisions/260602-09-azure-monitor-via-arc.md)
- [Research 17: Arc VM Insights root cause](../docs/research/17-arc-vm-insights-setup.md)
- [VM enable monitoring docs](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring)
