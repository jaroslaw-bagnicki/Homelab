# 14 — Backup Cost Comparison: Restic + Azure Blob vs Azure Backup Arc

**Source**: Azure retail pricing pages, June 14 2026  
**Scope**: Monthly cost comparison of cloud backup options for the M910q homelab server (Arc-enabled)

---

## Overview

The M910q homelab server is enrolled in Azure Arc (see [07-azure-arc-and-cost.md](07-azure-arc-and-cost.md)). This opens two cloud off-site backup paths:

1. **Restic → Azure Blob Storage** (partially set up — see [runbook 7](../runbooks/7-restic-backup.md))
2. **Azure Backup (MARS agent)** on the Arc-connected machine

Both use the same Azure subscription (`Cloud5-default`) and same resource group (`homelab-rg`). Both require the server to be connected to the internet during backup windows.

---

## Pricing Components

### Azure Blob Storage (Standard GPv2, LRS, Hot)

| Component | Price (USD) | Notes |
|---|---|---|
| Storage (first 50 TB) | **$0.018 / GB / month** | Hot tier, LRS, pay-as-you-go |
| Write operations | $0.065 / 10k ops | Daily restic backup writes |
| Read operations | $0.005 / 10k ops | Occasional restore / check |
| Data retrieval | Free (Hot tier) | No charge for reads |
| Data egress | $0.00 (same-region) | From Arc server to storage account both in Poland Central |
| **Management fee** | **$0** | No per-instance or per-server fee |

### Azure Backup (MARS Agent, Recovery Services Vault, LRS)

| Component | Price (USD) | Notes |
|---|---|---|
| Protected instance (≤ 50 GB) | $5 / month | Per server — data size before compression |
| Protected instance (> 50 GB, ≤ 500 GB) | **$10 / month** | Matches homelab estimate (~50–200 GB) |
| Protected instance (> 500 GB) | $10 per 500 GB increment | N/A for this scale |
| Backup storage (Standard, LRS) | **$0.0224 / GB / month** | Compressed backup data stored in vault |
| Archive tier storage | $0.0027 / GB / month | For retention > 6 months |
| **Management fee** | **$10 / month** | Fixed per-server protected-instance charge |

> Azure Backup does not charge for restore egress or data transfer from the vault (unlimited outbound data transfer).

---

## Monthly Cost Comparison

Assumptions:
- **Source data**: ~100 GB (Docker volumes, configs, compose files — the `homelab` stack)
- **Restic effective storage**: ~30–50 GB after deduplication (dedup is very effective for Docker volume snapshots)
- **Azure Backup effective storage**: ~60–80 GB after MARS agent compression (compression ratio is lower than restic dedup)
- **Write operations**: negligible cost for both (< $0.01/month)
- **Region**: Poland Central (pricing converted from USD at ~1:1 EUR rate for simplicity)

### Scenario: 100 GB source data

| Cost component | Restic → Blob (Hot, LRS) | Azure Backup (MARS, LRS) |
|---|---|---|
| Protected instance | — | **$10.00** |
| Storage (50 GB @ $0.018) | **$0.90** | — |
| Storage (70 GB @ $0.0224) | — | **$1.57** |
| Write operations | < $0.01 | Included |
| **Total / month** | **~$0.90** | **~$11.57** |

### Scenario: 200 GB source data

| Cost component | Restic → Blob (Hot, LRS) | Azure Backup (MARS, LRS) |
|---|---|---|
| Protected instance | — | **$10.00** |
| Storage (100 GB @ $0.018) | **$1.80** | — |
| Storage (140 GB @ $0.0224) | — | **$3.14** |
| Write operations | < $0.01 | Included |
| **Total / month** | **~$1.80** | **~$13.14** |

### Scenario: 50 GB source data

| Cost component | Restic → Blob (Hot, LRS) | Azure Backup (MARS, LRS) |
|---|---|---|
| Protected instance | — | **$5.00** |
| Storage (25 GB @ $0.018) | **$0.45** | — |
| Storage (35 GB @ $0.0224) | — | **$0.78** |
| **Total / month** | **~$0.45** | **~$5.78** |

---

## Annual Cost Projection

| Scenario | Restic → Blob (annual) | Azure Backup (annual) | Savings with Restic |
|---|---|---|---|
| 50 GB source | **~$5.40** | ~$69.36 | **12.8× cheaper** |
| 100 GB source | **~$10.80** | ~$138.84 | **12.9× cheaper** |
| 200 GB source | **~$21.60** | ~$157.68 | **7.3× cheaper** |

---

## Other Cost Factors

### One-time setup costs

| Item | Restic → Blob | Azure Backup |
|---|---|---|
| Restic binary | Free (open source) | — |
| MARS agent | — | Free (included) |
| Storage account | Storage account cost (~$1–2/mo for empty acct) | — |
| Recovery Services vault | — | Free (vault itself has no cost) |

### Restore (egress) costs

| Scenario | Restic → Blob | Azure Backup |
|---|---|---|
| Full restore (same region) | Free (data retrieval in Hot tier) | Free (unlimited outbound data transfer) |
| Cross-region restore | $0.01/GB (Blob data retrieval) | N/A (vault LRS stays in region) |
| Data transfer | Standard Bandwidth rates apply | Free |

### Retention impact

| Retention period | Restic → Blob | Azure Backup |
|---|---|---|
| 7 daily + 4 weekly + 6 monthly | Stored in Hot tier; dedup keeps growth low | Standard tier; older points can be moved to Archive ($0.0027/GB) |
| Long-term (> 6 months) | Sits in Hot — no auto-tiering | Can auto-tier to Archive — cheaper storage but early-deletion penalty if removed early |

---

## Qualitative Comparison

| Attribute | Restic → Blob (Hot, LRS) | Azure Backup (MARS, LRS) |
|---|---|---|
| **Monthly cost (100 GB)** | **~$0.90** | **~$11.57** |
| Encryption | AES-256 (restic built-in) | Microsoft-managed keys (AES-256) |
| Restore speed | Direct blob download (any blob tool) | Requires Azure Backup restore workflow |
| Restore flexibility | Any file, any snapshot — `restic restore` CLI | File-level or volume-level restore via portal/CLI |
| Automation | Systemd timer on the server | Azure Backup policy (built-in schedule) |
| Monitoring | `journalctl` + restic check | Azure Monitor / Backup Center dashboards |
| Arc dependency | None (standalone) | Works with or without Arc — Arc adds Backup Center visibility |
| Portal visibility | Manual — check blob container | Backup Center — unified view, alerts, reports |
| Learning curve | Moderate — restic CLI, env vars | Low — wizard-based, policy-driven |
| Portability | Full — blobs are standard, restic is open source | Vendor lock-in — can only restore via Azure Backup |
| Incremental efficiency | Dedup — very efficient for Docker volumes | Compression — good, but less efficient than dedup |
| Restore without internet | ❌ Requires internet | ❌ Requires internet |
| Offline restore path | Can copy blobs to a local restic repo | No offline option |

---

## Recommendation

**Restic → Azure Blob Storage remains the cost-effective choice** for this single-node homelab:

| Reason | Details |
|---|---|
| **12–13× cheaper** | No $10/month instance fee. Only pay for actual storage used. |
| **Dedup advantage** | Restic's block-level dedup is ideal for Docker volume snapshots — far less storage than Azure Backup's compression-only approach. |
| **Full portability** | Blobs are standard Azure Storage — can be downloaded, copied, or restored with any blob tool. No vendor lock-in. |
| **Partially set up** | Restic binary and config exist on the server; systemd timer and first backup still pending. Adding Azure Backup would be a second parallel system. |

**When Azure Backup would make sense:**

| Scenario | Why |
|---|---|
| Multi-server fleet (3+ Arc machines) | Instance fee amortizes; Backup Center gives unified management |
| Compliance requirement | Azure Backup provides audit-ready backup reports, policy enforcement |
| No dedicated backup ops | Azure Backup's policy-driven approach needs less ongoing attention |
| Need Archive tier for long-term retention | Archive at $0.0027/GB is 6.6× cheaper than Blob Hot at $0.018/GB |

**For this homelab**: Stick with Restic → Azure Blob (Hot, LRS). If long-term archival retention becomes important, add a weekly restic copy to Blob Cool tier ($0.01/GB) instead of switching to Azure Backup. That would cost ~$0.50–1.00/month for archival snapshots — still far below Azure Backup's $10 instance fee.

---

## References

- [Azure Blob Storage pricing (June 2026)](https://azure.microsoft.com/en-us/pricing/details/storage/blobs/)
- [Azure Backup pricing (June 2026)](https://azure.microsoft.com/en-us/pricing/details/backup/)
- [Runbook: Restic backup to Azure Blob](../runbooks/7-restic-backup.md)
- [Research: Azure Arc & cost comparison](07-azure-arc-and-cost.md)
- [Research: Backup strategy](10-backup-strategy.md)
