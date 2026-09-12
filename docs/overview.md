# Homelab at a Glance

High-level view of the current homelab: nodes and workloads. For the full per-node
hardware detail see [Hardware Inventory](hardware.md); for change history see
[CHANGELOG](../CHANGELOG.md); for step-by-step setup see the [Runbooks](runbooks/README.md).

**Status legend**: ✅ running · 🔨 in progress · 📋 planned · 🧠 idea

## Nodes

| Node | Role | Hardware / OS | IP | Status |
|---|---|---|---|---|
| **Lab** | main workload host (Docker → k3s) | Lenovo M910q Tiny · Ubuntu 24.04 LTS · Azure Arc | `192.168.2.200` | ✅ |
| **OMV NAS** | backup target (retiring) | HP ProLiant ML110 G5 · OMV 8.3 | `192.168.2.210` | ✅ |
| **Beetle NAS** | backup target (successor to ML110) | Wincor Beetle M-III · OS TBD (Unraid vs OMV) | DHCP | 🔨 |
| **Edge Ingress** | public ingress (cloudflared + Caddy) | Dell Wyse 3040 · Debian 13 minimal | `192.168.2.240` | 🔨 |
| **Home Assistant** | smart home node | Wyse 5070 · Proxmox VE | `192.168.2.201` | 🔨 |
| **LLM server** | local LLM inference | Minisforum X1 Lite | TBD | 🧠 |
| **Cloudlab VPS** | staging for Lab (Ansible + Docker/k3s workloads) | Contabo VPS 10 · Ubuntu 24.04 | `173.249.27.13` | ✅ |

## Workloads

Current state — what's running or in progress. Planned work is under [What's Next](#whats-next).

| Workload | Runs on | Purpose | Status |
|---|---|---|---|
| **Portainer CE** | Cloudlab VPS | Docker GUI | ✅ |
| **Caddy** | Cloudlab VPS | reverse proxy + auto-TLS | ✅ |
| **cloudflared** | Cloudlab VPS | Cloudflare Tunnel public HTTPS | ✅ |
| **OpenCode instances** (`homelab`, `prospera`) | Cloudlab VPS | per-project agentic dev servers | ✅ |
| **Zot** | Cloudlab VPS | self-hosted OCI registry + pull-through cache | ✅ |
| **OpenMediaVault** | OMV NAS | network shares (SMB) + backup target | ✅ |

## What's Next

Planned and in-progress work only, listed in execution order. The backlog lives in
[Issues](https://github.com/jaroslaw-bagnicki/Homelab/issues) and is pulled in here
once it is ready to start — a row leaves the table with the PR that completes it.

**Effort**: ⭐ one session · ⭐⭐ a few sessions · ⭐⭐⭐ multi-week or hardware-gated

### In progress

| Item | Effort | Next step | Refs |
|---|---|---|---|
| **Netdata Parent + `netdata` role** | ⭐⭐ | Parent LXC on the HA Proxmox, then the Lab (M910q) host-native child, then re-point the remaining children | [#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104) · [ADR 27](decisions/27-monitoring-strategy.md) |
| **Edge Ingress — service migration** | ⭐⭐ | Move `cloudflared` + Caddy + dnsmasq off the M910q onto the Wyse 3040 (base OS + `edge_host` role already shipped) | [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) · [#81](https://github.com/jaroslaw-bagnicki/Homelab/issues/81) · [runbook 24](runbooks/24-edge-appliance.md) |
| **Beetle NAS** | ⭐⭐⭐ | Replacement unit arriving — re-audit the spec, then OS decision (Unraid vs OMV) → array + cache online → NFS/SMB exports + Longhorn target → retire the ML110 | [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) · [idea 01c](ideas/01c-nas-backup-target-wincor-beetle.md) |
| **Home Assistant node** | ⭐⭐⭐ | VM 100 (HA OS) + LXC 101/102 (Mosquitto, Zigbee2MQTT) on the Proxmox base from runbook 28 — the Z2M LXC feeds power monitoring | [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) · [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85) · [ADR 25](decisions/25-home-assistant-thin-client.md) |

### Planned

| Item | Effort | Next step | Refs |
|---|---|---|---|
| **UPS + NUT graceful shutdown** | ⭐⭐ | Unit arriving — record the model + USB controller, then NUT server on the HA node and the fleet-wide clients | [#111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111) · [idea 09](ideas/09-ups-nut-home-assistant.md) |
| **Netdata children — Edge (RAM-only), HA, OMV** | ⭐ | Re-point onto the Parent once it lands | [#80](https://github.com/jaroslaw-bagnicki/Homelab/issues/80) · [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) |
| **Power monitoring (Zigbee/Z2M)** | ⭐⭐ | Zigbee energy plugs → Prometheus, after the HA node's Z2M LXC — sequenced **before** k3s | [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) · [ADR 26](decisions/26-zigbee-energy-monitoring.md) |
| **YUMI multiboot USB standard** | ⭐ | ADR 29 + manage-YUMI runbook; de-conflate the Ventoy references | [#107](https://github.com/jaroslaw-bagnicki/Homelab/issues/107) · [research 12](research/12-first-boot-setup.md) |

### Held

| Item | Waiting on | Refs |
|---|---|---|
| **OPNsense router (Futro S930)** | power cable for the SSD — order it, then install | [#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96) · [research 31](research/31-futro-s930-hardware-diagnostic.md) |
| **k3s migration** | deliberate sequencing — largest item, gates NFS/Longhorn and #48 | [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44) · [ADR 22](decisions/22-k3s-arc-homelab.md) |

## Not Scheduled

Parked work with no start date. An item moves to [What's Next](#whats-next) when it is
ready to start.

| Item | Parked because | Refs |
|---|---|---|
| **Restic backup** (redo) | dormant since June; ADR 02 still reads *In Progress* | [#13](https://github.com/jaroslaw-bagnicki/Homelab/issues/13) · [ADR 02](decisions/02-backup-strategy-restic-blob.md) · [runbook 07](runbooks/07-restic-backup.md) |
| **SQL Server Developer Edition** | never started | [#3](https://github.com/jaroslaw-bagnicki/Homelab/issues/3) · [runbook 09](runbooks/09-mssql-dev.md) |
| **Gitea** | never started | [#4](https://github.com/jaroslaw-bagnicki/Homelab/issues/4) |
| **Hermes Agent** | most complex — deliberately last | — |
| **Ollama + Bielik** (Phase 2) | needs the LLM server hardware first | — |

## Topology

```
ISP fiber router (192.168.1.0/24)
        │
Tenda Nova mesh — 192.168.2.0/24, gateway 192.168.2.1 (single broadcast domain)
        │
        └── TL-SG108E switch (192.168.2.230)
                 ├── Lab M910q        — 192.168.2.200
                 ├── OMV NAS         — 192.168.2.210
                 ├── Edge Ingress      — 192.168.2.240
                 ├── Home Assistant    — 192.168.2.201
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
