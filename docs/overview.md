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
| **Beetle NAS** | backup target (successor to ML110) | Wincor Beetle M-III · OMV | DHCP | 🔨 |
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
| **Netdata Parent + `netdata` role** | ⭐⭐ | Parent LXC on the HA Proxmox, then re-point the children | [#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104) · [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) · [ADR 27](decisions/27-monitoring-strategy.md) |
| **Edge Ingress — service migration** | ⭐⭐ | Move `cloudflared` + Caddy off the M910q onto the Wyse 3040 (base OS + `edge_host` role already shipped); `.home` DNS is owned by the OPNsense router, not the edge | [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) · [#81](https://github.com/jaroslaw-bagnicki/Homelab/issues/81) · [ADR 24](decisions/24-edge-ingress-appliance.md) |
| **Beetle NAS** | ⭐⭐⭐ | Replacement unit arriving — re-audit the spec, then OMV install → array + cache online → NFS/SMB exports → retire the ML110 (the Longhorn backup target follows k3s) | [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) · [ADR 29](decisions/29-nas-backup-target-beetle-m3-omv.md) |
| **Home Assistant node** | ⭐⭐⭐ | VM 100 (HA OS) + LXC 101/102 (Mosquitto, Zigbee2MQTT) on the Proxmox base from runbook 28 | [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) · [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85) · [ADR 25](decisions/25-home-assistant-thin-client.md) |

### Planned

| Item | Effort | Next step | Refs |
|---|---|---|---|
| **UPS + NUT graceful shutdown** | ⭐⭐ | Unit on the HA node (`0665:5161`, runbook 29) — execute it: LXC 103 + `nutdrv_qx` probe, then the PVE host and the `lab`/`edge` clients | [#111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111) · [runbook 29](runbooks/29-nut-ups-shutdown.md) |
| **Netdata children — Edge (RAM-only), Lab (host-native), OMV, Beetle** | ⭐ | Re-point onto the Parent once it lands — HA runs the Parent itself, so it is not a child | [#80](https://github.com/jaroslaw-bagnicki/Homelab/issues/80) · [#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104) |
| **Power monitoring (Zigbee/Z2M)** | ⭐⭐ | Zigbee energy plugs → Prometheus, bootstrapped standalone on the M910q (ADR 26 — independent of Home Assistant) — sequenced **before** k3s | [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) · [ADR 26](decisions/26-zigbee-energy-monitoring.md) |
| **YUMI multiboot USB standard** | ⭐ | ADR 29 + manage-YUMI runbook; de-conflate the Ventoy references | [#107](https://github.com/jaroslaw-bagnicki/Homelab/issues/107) · [research 12](research/12-first-boot-setup.md) |

### Held

| Item | Waiting on | Refs |
|---|---|---|
| **OPNsense router (Futro S930)** | power cable for the replacement SSD — order it, then install (the fitted 7.99 GB mSATA is undersized) | [#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96) · [research 31](research/31-futro-s930-hardware-diagnostic.md) |
| **k3s migration** | deliberate sequencing — largest item, gates the Longhorn backup target and #48 | [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44) · [ADR 22](decisions/22-k3s-arc-homelab.md) |

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
