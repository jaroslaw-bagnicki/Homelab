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
| **Beetle NAS** | backup target (successor to ML110) | Wincor Beetle M-III · OMV 8.5 | `192.168.2.202` | 🔨 |
| **Edge Ingress** | public ingress (cloudflared + Caddy) | Dell Wyse 3040 · Debian 13 minimal | `192.168.2.240` | 🔨 |
| **Proxmox VE** | virtualisation host — smart-home + always-on services | Dell Wyse 5070 | `192.168.2.201` · guests `.210`–`.213` | 🔨 |
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
| **Netdata Parent** | Proxmox VE host (`pve`) | Tier B central monitoring pane — aggregates per-node metrics from Lab + Edge + Beetle NAS (`nas`) children | ✅ |
| **UPS + NUT** | `pve` (LXC 213) + `lab`/`edge`/`nas` clients | shared-rail power protection — `upsmon` stops each node in order on low battery | ✅ |

## Observability

Two tiers, split by plane rather than by tool ([ADR 27](decisions/27-monitoring-strategy.md)) — the
Azure **management plane** and the local **real-time plane**.

| Signal | Path | Status |
|---|---|---|
| **Per-node metrics** | Netdata — Parent host-native on the `pve` node, children on `lab`/`edge`/`nas`; HTTPS-only dashboard, TLS-only streaming, 7-day retention; LAN-only and unauthenticated, alarm delivery waits on the HA VM ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)) | ✅ |
| **Cloud telemetry** | Azure Monitor via Arc — AMA → Log Analytics `homelab-law` (`VmInsights\DetailedMetrics` DCR) on Arc-enrolled nodes; Container Insights joins with k3s ([ADR 09](decisions/09-azure-monitor-via-arc.md)) | ✅ |
| **Power state** | NUT in LXC 213 — `upsmon` events drive the ordered fleet shutdown, `upsc` for ad-hoc reads ([ADR 30](decisions/30-ups-nut-graceful-shutdown.md)) | ✅ |
| **Disk health** | SMART plus long self-tests on the NAS arrays (OMV SMART page), findings recorded per drive | ✅ |
| **Per-device energy** | Zigbee plugs → Zigbee2MQTT → MQTT → `mqtt2prometheus` → Prometheus → Grafana ([#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) · [ADR 26](decisions/26-zigbee-energy-monitoring.md)) | 📋 |
| **Logs** | Tier B log store — **VictoriaLogs** favoured over Loki (decision pending), TLS + basic auth from day one; collector and retention still open ([#123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123) · [ADR 34](decisions/34-lan-tls-only.md)) | 🔨 |

**Boundary rule**: Arc is the management plane (policy, compliance, portal, heartbeat) and covers
only Arc-enrolled nodes, while per-node real-time metrics come from Netdata on **every** LAN node —
the Edge appliance and `pve` are never Arc-enrolled, so Azure alone can never see the whole fleet.

## What's Next

Planned and in-progress work only, listed in execution order. The backlog lives in
[Issues](https://github.com/jaroslaw-bagnicki/Homelab/issues) and is pulled in here
once it is ready to start — a row leaves the table with the PR that completes it.

**Effort**: ⭐ one session · ⭐⭐ a few sessions · ⭐⭐⭐ multi-week or hardware-gated

### In progress

| Item | Effort | Next step | Refs |
|---|---|---|---|
| **Edge Ingress — service migration** | ⭐⭐ | Move `cloudflared` + Caddy off the M910q onto the Wyse 3040 (base OS + `edge_host` role already shipped); `.home` DNS is owned by the OPNsense router, not the edge | [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) · [#81](https://github.com/jaroslaw-bagnicki/Homelab/issues/81) · [ADR 24](decisions/24-edge-ingress-appliance.md) |
| **Beetle NAS** | ⭐⭐⭐ | **Phase 1 done** — OMV 8.5 on `nas`, `md0` RAID1 clean + reboot-verified, fleet-enrolled with the Netdata child and NUT secondary; next: create the share and move the backup target, then retire the ML110 and release `.210` (Memtest86+ and the RTC coin cell stay deferred — [research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md)) | [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) · [ADR 29](decisions/29-nas-backup-target-beetle-m3-omv.md) · [runbook 32](runbooks/32-beetle-m3-omv-setup.md) |
| **Home Assistant VM + LXCs** | ⭐⭐⭐ | VM 210 (HA OS) + LXC 211/212 (Mosquitto, Zigbee2MQTT) on the `pve` node (the base from runbook 28), then point HA's NUT integration at `192.168.2.213` for UPS status + power-loss notifications | [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) · [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85) · [ADR 25](decisions/25-home-assistant-thin-client.md) · [#111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111) |
| **Log store (VictoriaLogs)** | ⭐⭐ | Stand up the Tier B log store for the fleet's journals — **VictoriaLogs favoured over Loki** (single binary, log-native query, RAM-light), decision not yet recorded; ADR first, then an LXC on `pve` with TLS + HTTP basic auth and container-level filtering | [#123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123) · [ADR 27](decisions/27-monitoring-strategy.md) · [ADR 34](decisions/34-lan-tls-only.md) |

### Planned

| Item | Effort | Next step | Refs |
|---|---|---|---|
| **Power monitoring (Zigbee/Z2M)** | ⭐⭐ | Zigbee energy plugs → Prometheus, bootstrapped standalone on the M910q (ADR 26 — independent of Home Assistant) — sequenced **before** k3s | [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) · [ADR 26](decisions/26-zigbee-energy-monitoring.md) |
| **YUMI multiboot USB standard** | ⭐ | ADR 29 + manage-YUMI runbook; de-conflate the Ventoy references | [#107](https://github.com/jaroslaw-bagnicki/Homelab/issues/107) · [research 12](research/12-first-boot-setup.md) |

### Held

| Item | Waiting on | Refs |
|---|---|---|
| **OPNsense router (Futro S930)** | power cable for the replacement SSD — order it, then install (the fitted 7.99 GB mSATA is undersized) | [#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96) · [research 31](research/31-futro-s930-hardware-diagnostic.md) |
| **k3s migration** | deliberate sequencing — largest item, gates the Longhorn backup target and #48 | [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44) · [ADR 22](decisions/22-k3s-arc-homelab.md) |
| **Beetle on battery — modified-sine re-test** | replacement UPS unit — OMV now runs on the Beetle ([#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)) and its `nut_client` secondary is live (runbook 32 §8), so the active-PFC supply can finally be tested on a real load | [#117](https://github.com/jaroslaw-bagnicki/Homelab/issues/117) · [runbook 29](runbooks/29-nut-ups-shutdown.md) §7 · [report](reports/260919-nut-shutdown-drill.md) |

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
                 ├── Proxmox VE       — 192.168.2.201
                 ├── OMV NAS          — 192.168.2.210
                 ├── Beetle NAS       — 192.168.2.202
                 ├── Edge Ingress     — 192.168.2.240
                 └── work laptop dock — DHCP (corporate)
```

**Power**: both strips sit behind the shared-rail **Green Cell UPSLM600** — USB on the `pve` node,
NUT server in LXC 213, `upsmon` on `pve`/`lab`/`edge`/`nas`
([ADR 30](decisions/30-ups-nut-graceful-shutdown.md)).

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
