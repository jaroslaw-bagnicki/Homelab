# Homelab at a Glance

High-level view of the current homelab: nodes and workloads. For the full per-node
hardware detail see [Hardware Inventory](hardware.md); for change history see
[CHANGELOG](../CHANGELOG.md); for step-by-step setup see the [Runbooks](runbooks/README.md).

**Status legend**: ✅ running · 🔨 in progress · 📋 planned · 🧠 idea

## Nodes

| Node | Role | Hardware / OS | IP | Status |
|---|---|---|---|---|
| **Homelab** | main workload host (Docker → k3s) | Lenovo M910q Tiny · Ubuntu 24.04 LTS · Azure Arc | `192.168.2.200` | ✅ |
| **OMV NAS** | backup target / NFS for Longhorn | HP ProLiant ML110 G5 · OMV 8.3 | `192.168.2.210` | ✅ |
| **Edge Ingress** | public ingress (cloudflared + Caddy) | Dell Wyse 3040 · Debian/Alpine TBD | TBD | 🔨 |
| **Home Assistant** | smart home node | Wyse 5070 · Proxmox VE | TBD | 📋 |
| **LLM server** | local LLM inference | Minisforum X1 Lite | TBD | 🧠 (Phase 2) |
| **Cloudlab VPS** | staging / Ansible playground | Contabo VPS 10 · Ubuntu 24.04 | `173.249.27.13` | ✅ |

## Workloads

Current state — what's running or in progress. Planned work is under [What's Next](#whats-next).

| Workload | Runs on | Purpose | Status |
|---|---|---|---|
| **Portainer CE** | Cloudlab VPS | Docker GUI | ✅ |
| **Caddy** | Cloudlab VPS | reverse proxy + auto-TLS | ✅ |
| **cloudflared** | Cloudlab VPS | Cloudflare Tunnel public HTTPS | ✅ |
| **OpenCode instances** (`homelab`, `prospera`) | Cloudlab VPS | per-project agentic dev servers | ✅ |
| **Zot** | Cloudlab VPS | self-hosted OCI registry + pull-through cache | ✅ |
| **OMV NAS shares** | OMV NAS | SMB `/shared` backup share live (SMB3 transport encryption required + `rescuezilla` user — unblocks #79); NFS `/export/backups` + Longhorn pending (k3s #44) | 🔨 (Phase 2) |

## What's Next

| # | Workload | Effort | Notes |
|---|---|---|---|
| [#13](https://github.com/jaroslaw-bagnicki/Homelab/issues/13) | **Restic backup** (redo) | ⭐⭐ | Daily snapshots to Azure Blob Storage — see [runbook](runbooks/07-restic-backup.md) |
| [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) | **Edge Ingress** | ⭐⭐ | Move public ingress (`cloudflared` + Caddy) to the Wyse 3040 — [runbook 24](runbooks/24-edge-appliance.md) · [ADR 24](decisions/24-edge-ingress-appliance.md) |
| [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) | **OMV NAS Phase 2** | ⭐⭐ | NFS/SMB exports + Longhorn backup target — [runbook 26](runbooks/26-ml110-nas-exports.md) · SMB `/shared` done (unblocks #79) |
|  | **Home Assistant** | ⭐⭐ | Dedicated HA node — Proxmox VE VM + MQTT/Zigbee2MQTT — [idea 05](ideas/05-home-assistant-thin-client.md) · [ADR 25](decisions/25-home-assistant-thin-client.md) |
| [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44) | **k3s migration** | ⭐⭐⭐ | Migrate workloads from Docker Compose to Kubernetes (k3s + Arc) — per [ADR 22](decisions/22-k3s-arc-homelab.md) |
|  | **Hermes Agent** | ⭐⭐⭐ | Most complex — last |
| [#3](https://github.com/jaroslaw-bagnicki/Homelab/issues/3) | **SQL Server** | ⭐⭐ | Developer Edition in Docker — see [runbook](runbooks/09-mssql-dev.md) |
| [#4](https://github.com/jaroslaw-bagnicki/Homelab/issues/4) | **Gitea** | ⭐⭐ | Self-hosted Git with web UI for personal repos |
| - | **Ollama + Bielik** (Phase 2) | ⭐⭐⭐ | Needs dedicated LLM server hardware |

## Topology

```
ISP fiber router (192.168.1.0/24)
        │
Tenda Nova mesh — 192.168.2.0/24, gateway 192.168.2.1 (single broadcast domain)
        │
        └── TL-SG108E switch (192.168.2.230)
                 ├── Homelab M910q    — 192.168.2.200
                 ├── OMV NAS         — 192.168.2.210
                 ├── Edge Ingress      — TBD (future ingress)
                 └── work laptop dock — DHCP (corporate)
```

Cloudlab VPS (Contabo) sits outside the LAN with its own Cloudflare Tunnel + Caddy (ADR 19).

## Project Structure

| Folder | Purpose |
|---|---|
| [`ansible/`](../ansible/README.md) | Host provisioning — playbooks, roles (common, security, azure_arc, docker_host, docker_services, workloads), inventory |
| [`bicep/`](../bicep/README.md) | Cloud-side IaC — Log Analytics, DCR, AMA extensions, Key Vault |
| [`scripts/`](../scripts/) | Standalone PowerShell utilities (SSH key management, Arc client secrets, OpenCode backup) |

Ansible runs first on the bare host (OS config, Docker, Arc agent). Bicep deploys cloud resources after Arc enrolment. The decision log is the source of truth for design rationale. Runbooks capture implementation steps. Research docs capture exploratory context that predates settled decisions. Ideas capture possibilities before a decision is made.

---

See [Hardware Inventory](hardware.md) for per-node specs, drives, and network appliances.
