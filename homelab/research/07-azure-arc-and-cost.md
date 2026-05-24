# 07 — Azure Integration: Arc & Cost Comparison

**Source**: Gemini 3.5 Flash conversation, May 20 2026  
**Scope**: Azure Arc for hybrid management, cost comparison between physical homelab and Azure equivalents

---

## Cost Comparison: Physical vs Cloud

Running the equivalent of an M910q lab in Azure 24/7 (4 vCPU, 16 GB RAM, 256 GB disk, public IP) is dramatically more expensive than owning the hardware.

### Azure VM (IaaS) — Standard_B4ms

| Component | Spec | Monthly cost (estimate) |
|---|---|---|
| Compute (B4ms) | 4 vCPU, 16 GB RAM, 24/7 | ~$75 |
| Disk (Premium SSD v2) | 256 GiB | ~$22 |
| Public IP + bandwidth | Static IP + ~100 GB egress | ~$5 |
| **Total** | | **~$102 / month (~440 PLN)** |

### Azure Container Apps (PaaS)

| Component | Spec | Monthly cost (estimate) |
|---|---|---|
| Dedicated Workload Profile | 4 vCPU / 16 GiB, 24/7 | ~$225 |
| Management fee | $0.10/h × 730 h | ~$73 |
| Azure Files (Premium) | 256 GB for volumes | ~$35 |
| **Total** | | **~$333 / month (~1400 PLN)** |

### Physical M910q

| Component | Cost |
|---|---|
| Hardware (second-hand, Allegro) | ~400–550 PLN one-time |
| Electricity @ 10 W avg, 8760 h/yr | ~88 kWh → ~85–110 PLN/year |
| **Year 1 total** | **~500–660 PLN** |
| **Year 2+ annual** | **~85–110 PLN** |

> One month of the cheapest Azure VM equivalent costs as much as buying the physical machine.  
> After one year in Azure: ~5 000+ PLN spent. Physical lab: ~550 PLN total.

### Recommended Hybrid Approach

- **Local**: homelab container stack, Home Assistant, Hermes Agent, Docker workloads
- **Azure (minimal / free/cheap)**:
  - Azure Key Vault (minimal cost) — store secrets securely
  - Azure Functions (Consumption tier free tier) — webhook processing if needed
  - Azure Blob Storage (smallest tier) — encrypted off-site backups of config/data volumes

---

## Azure Arc — Enrolling the M910q

Azure Arc lets you register a non-Azure machine as a managed server in your Azure subscription. The physical M910q appears in the Azure Portal alongside cloud VMs.

### What Arc enables

| Feature | Details |
|---|---|
| Single pane of glass | See the homelab server in Azure Portal alongside cloud resources |
| Azure Policy | Enforce OS update policies, security baselines on the physical machine |
| Azure Monitor / Log Analytics | Ship system metrics and logs to Azure Monitor; query with KQL |
| Azure Update Management | Schedule and audit Ubuntu patch cycles from Azure |
| Grafana integration | Build dashboards combining homelab telemetry with cloud resource data |

### Enrollment Process

1. In Azure Portal → search **Azure Arc** → Servers → Add a single server
2. Choose **Linux** target → generate the installation script
3. On the M910q (via SSH), run the generated script:

```bash
# Example form of the generated script (actual script varies per subscription)
sudo bash install_linux_azcmagent.sh \
  --resource-group "homelab-rg" \
  --tenant-id "YOUR_TENANT_ID" \
  --location "westeurope" \
  --subscription-id "YOUR_SUBSCRIPTION_ID"
```

4. Authenticate when prompted (device code flow)
5. The machine appears in the Azure Portal within a few minutes

### Arc Agent resource usage

The Azure Connected Machine Agent (`azcmagent`) is lightweight:
- CPU: <1% average
- RAM: ~50–80 MB
- Network: periodic heartbeat and log shipping (no significant bandwidth)

### Costs

Azure Arc for servers is **free** for up to 3 servers in the free tier. Charges apply only if you enable paid Azure services on the Arc server (e.g. full Log Analytics ingestion at scale, Defender for Cloud).

---

## Decision for This Project

| Capability | Use it? | Notes |
|---|---|---|
| Azure Arc enrollment | ✅ Yes | Useful for monitoring, patch management; zero additional cost at this scale |
| Azure Monitor Log Analytics | ✅ Yes (limited) | Free tier (5 GB/month ingestion) covers homelab telemetry easily |
| Azure Key Vault | ✅ Yes | Store Hermes API keys and other secrets; ~$0.03/10 000 operations |
| Azure VM as primary lab | ❌ No | 10–20× more expensive than physical for equivalent resources |
| Azure Container Apps | ❌ No | Only viable if horizontal scaling or SLA is required |
