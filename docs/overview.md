# Homelab at a Glance

High-level view of the current homelab: nodes and workloads. For the full per-node
hardware detail see [Hardware Inventory](hardware.md); for change history see
[CHANGELOG](../CHANGELOG.md); for step-by-step setup see the [Runbooks](runbooks/README.md).

**Status legend**: ✅ running · 🔨 in progress · 📋 planned · 🧠 idea

## Nodes

| Node | Role | Hardware / OS | IP | Status |
|---|---|---|---|---|
| **Homelab** | main workload host (Docker → k3s) | Lenovo M910q Tiny · Ubuntu 24.04 | `192.168.2.200` | ✅ |
| **ML110 NAS** | backup target / NFS for Longhorn | HP ProLiant ML110 G5 · OMV 8.3 | `192.168.2.210` | ✅ |
| **TL-SG108E** | access switch | TP-Link 8× GigE (L2) | `192.168.2.230` | ✅ |
| **Cloudlab** | staging / Ansible playground | Contabo VPS 10 · Ubuntu 24.04 | `173.249.27.13` | ✅ |
| **Edge appliance** | public ingress (cloudflared + Caddy) | Dell Wyse 3040 · Debian/Alpine TBD | TBD | 🔨 |
| **HA thin client** | smart home node (Home Assistant) | Wyse 5070 · Proxmox VE | TBD | 📋 |
| **X1 Lite LLM server** | local LLM inference | Minisforum X1 Lite | TBD | 🧠 (Phase 2) |

## Workloads

| Workload | Runs on | Purpose | Status |
|---|---|---|---|
| **Portainer CE** | Cloudlab | Docker GUI | ✅ |
| **Caddy** | Cloudlab | reverse proxy + auto-TLS | ✅ |
| **cloudflared** | Cloudlab | Cloudflare Tunnel public HTTPS | ✅ |
| **OpenCode instances** (`homelab`, `prospera`) | Cloudlab | per-project agentic dev servers | ✅ |
| **Zot** | Cloudlab | self-hosted OCI registry + pull-through cache | ✅ |
| **OMV NAS shares** | ML110 | NFS/SMB exports, Longhorn backup target | 🔨 (Phase 2) |
| **Restic backup** | Homelab | snapshots to Azure Blob | 📋 |
| **SQL Server** | Homelab | Developer Edition in Docker | 📋 |
| **Gitea** | Homelab | self-hosted Git | 📋 |
| **Hermes Agent** | Homelab | AI agent | 📋 |
| **k3s + Azure Arc** | Homelab | Kubernetes migration (ADR 22) | 📋 |

## Topology

```
ISP fiber router (192.168.1.0/24)
        │
Tenda Nova mesh — 192.168.2.0/24, gateway 192.168.2.1 (single broadcast domain)
        │
        └── TL-SG108E switch (192.168.2.230)
                 ├── Homelab M910q    — 192.168.2.200
                 ├── ML110 NAS (OMV)  — 192.168.2.210
                 ├── Edge appliance   — TBD (future ingress)
                 └── work laptop dock — DHCP (corporate)
```

Cloudlab (Contabo VPS) sits outside the LAN with its own Cloudflare Tunnel + Caddy (ADR 19).

---

See [Hardware Inventory](hardware.md) for per-node specs, drives, and network appliances.
