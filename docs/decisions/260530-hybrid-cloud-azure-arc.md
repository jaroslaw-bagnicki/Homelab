# Hybrid Cloud Strategy — Physical Homelab + Minimal Azure

**Date:** 2026-05-30
**Status:** Implemented

---

## Context

Services for the homelab could run either on the physical M910q (one-time cost ~620 PLN, ~10 W idle) or entirely in Azure cloud. The decision affects monthly cost, operational complexity, and management surface.

## Decision

Adopt a **hybrid approach**: run workloads locally on the physical M910q, use Azure for management (Arc) and minimal-cost cloud services (Key Vault, Blob Storage, Functions consumption tier).

Key factors:
- **Cost dominance** — one month of the cheapest Azure VM equivalent (B4ms, $102/month) costs as much as buying the hardware. After one year in Azure: ~$1,224 vs ~$660 total for physical including electricity
- **Arc management** — enroll the M910q in Azure Arc for a unified Azure Portal view, Azure Policy enforcement, and Azure Monitor telemetry — no need to run workloads in Azure to get cloud management
- **Minimal cloud services** — Azure Key Vault (pennies/month) for secrets, Azure Blob Storage (pennies/GB) for off-site backups, Azure Functions (consumption free tier) for webhook processing — negligible cost, high value
- **Local data** — personal data stays on local disk; cloud is used only for management and backup

Rejected alternatives:
- **Full cloud (Azure VMs)** — $102+/month for a comparable VM; not justified for a 24/7 experimental homelab
- **Full cloud (Azure Container Apps)** — $333/month for a comparable profile; uneconomical for any personal project
- **No cloud at all** — no Arc management surface, no off-site backup target, no Key Vault for secrets — acceptable in principle but the minimal cloud tier adds resilience at negligible cost

## Consequences

- Single pane of glass in Azure Portal shows the homelab alongside any future cloud resources
- Azure Policy can enforce OS patch baselines on the physical machine
- Azure Monitor ships metrics and logs to Log Analytics for KQL querying
- Key Vault provides a centralized secrets store accessible by both local and cloud workloads
- Minimal cloud cost (~$1–3/month for Blob storage + Key Vault + occasional Functions executions)
- VPN is not required for cloud services — Arc agent communicates outbound, Blob storage is accessed via REST API with managed identity or key
