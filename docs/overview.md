# Homelab at a Glance

High-level view of the current homelab: nodes and workloads. For the full per-node
hardware detail see [Hardware Inventory](hardware.md); for change history see
[CHANGELOG](../CHANGELOG.md); for step-by-step setup see the [Runbooks](runbooks/README.md).

**Status legend**: ✅ running · 🔨 in progress · 📋 planned · 🧠 idea · 🪦 retired

## Nodes

| Node | Role | Hardware / OS | Hostname | IP | Status |
|---|---|---|---|---|---|
| **Lab** | main workload host (Docker → k3s) | Lenovo M910q Tiny · Ubuntu 24.04 LTS · Azure Arc | `lab` | `192.168.2.200` | 🔨 |
| **OMV NAS** | backup target | HP ProLiant ML110 G5 · OMV 8.3 | `omv` | `192.168.2.210` | 🪦 |
| **Beetle NAS** | backup target (successor to ML110) | Wincor Beetle M-III · OMV 8.5 | `nas` | `192.168.2.202` | 🔨 |
| **Edge Ingress** | LAN DNS + reverse proxy (public ingress held) | Dell Wyse 3040 · Debian 13 minimal | `edge` | `192.168.2.240` | ✅ |
| **Proxmox VE** | virtualisation host — smart-home + always-on services | Dell Wyse 5070 | `pve` | `192.168.2.201` · guests `.210`–`.212`, `.214` | ✅ |
| **LLM server** | local LLM inference | Minisforum X1 Lite | — | TBD | 🧠 |
| **Cloudlab VPS** | staging for Lab (Ansible + Docker/k3s workloads) | Contabo VPS 10 · Ubuntu 24.04 | `cloudlab` | `173.249.27.13` | ✅ |

### Guests on the Proxmox VE node

| Guest | Workload | Hostname | Address | Status |
|---|---|---|---|---|
| VM 210 | Home Assistant OS | — | `.210` | 📋 |
| LXC 211 | Mosquitto | — | `.211` | 📋 |
| LXC 212 | Zigbee2MQTT | — | `.212` | 📋 |
| LXC 213 | NUT server — retired, moved host-native to `pve` | `nut` | `.213` | 🪦 |
| LXC 214 | VictoriaLogs log store | `vtstack` | `.214` | ✅ |
| LXC 215 | Private CA (`step-ca`) | `ca` | `.215` | ✅ |

The NUT server now runs **host-native on `pve`** ([ADR 39](decisions/39-nut-host-native.md)); LXC 213 is retired and `.213` is free.

Addresses follow the static scheme ([ADR 31](decisions/31-static-address-scheme.md)); node hostnames name the host role ([ADR 33](decisions/33-fleet-node-hostnames.md)); the workload platform is migrating to k3s ([ADR 22](decisions/22-k3s-arc-homelab.md)).

## Workloads

Current state — what's running or in progress. Planned work is under [What's Next](#whats-next).

| Workload | Runs on | Purpose | Refs | Status |
|---|---|---|---|---|
| **Portainer CE** | `cloudlab` | Docker GUI | [runbook 16](runbooks/16-docker-services-ansible-role.md) | ✅ |
| **Caddy** | `cloudlab` | reverse proxy + auto-TLS | [ADR 20](decisions/20-caddy-single-routing-layer.md) · [runbook 16](runbooks/16-docker-services-ansible-role.md) | ✅ |
| **cloudflared** | `cloudlab` | Cloudflare Tunnel public HTTPS | [ADR 19](decisions/19-cloudflare-tunnel-http-origin.md) · [runbook 16](runbooks/16-docker-services-ansible-role.md) | ✅ |
| **OpenCode instances** (`homelab`, `prospera`) | `cloudlab` | per-project agentic dev servers | [ADR 17](decisions/17-adopt-opencode.md) · [runbook 17](runbooks/17-deploy-opencode-on-cloudlab.md) | ✅ |
| **Zot** | `cloudlab` | self-hosted OCI registry + pull-through cache | [runbook 20](runbooks/20-deploy-zot.md) | ✅ |
| **OpenMediaVault** | `omv` | network shares (SMB) + backup target | [ADR 23](decisions/23-nas-on-ml110.md) | 🪦 |
| **Netdata Parent** | `pve` | Tier B central monitoring pane | [ADR 27](decisions/27-monitoring-strategy.md) · [runbook 31](runbooks/31-deploy-netdata.md) | ✅ |
| **UPS + NUT** | `pve` (host-native NUT server) + `lab`/`edge`/`nas` clients | shared-rail power protection | [ADR 39](decisions/39-nut-host-native.md) · [runbook 29](runbooks/29-nut-ups-shutdown.md) · [runbook 30](runbooks/30-deploy-nut-clients.md) | ✅ |
| **VictoriaLogs** | `pve` (LXC 214 `vtstack`) | Tier B log store | [ADR 35](decisions/35-log-store-victorialogs.md) · [runbook 33](runbooks/33-deploy-victorialogs.md) | ✅ |
| **Private CA** (`step-ca`) | `pve` (LXC 215 `ca`) | fleet trust anchor — ACME issuance, intermediate sealed in the `pve` TPM | [ADR 38](decisions/38-private-ca-hierarchy-and-custody.md) · [runbook 35](runbooks/35-deploy-step-ca.md) | ✅ |
| **Fluent Bit** | every LAN node (`pve`, `edge`, `lab`, `nas`, `vtstack`) | Tier B log collector — ships journald + Docker logs to VictoriaLogs | [ADR 36](decisions/36-log-collector-fluentbit.md) · [runbook 34](runbooks/34-deploy-fluentbit.md) | ✅ |
| **Internal access stack** (Technitium DNS + Caddy) | `edge` | authoritative `internal.` DNS + LAN reverse proxy with short-lived `step-ca` leaves | [ADR 40](decisions/40-internal-dns-proxy-edge.md) · [runbook 37](runbooks/37-deploy-internal-access-stack.md) | ✅ |

## Observability

Two tiers, split by plane rather than by tool ([ADR 27](decisions/27-monitoring-strategy.md)) — Azure
watches the **management plane**, the LAN watches the **real-time plane**. Where each signal is seen:

| Signal | Where you see it | Refs | Status |
|---|---|---|---|
| **Node metrics** | Netdata — centralized monitoring and alerting for every LAN node; 3-tier retention up to 1y | [ADR 27](decisions/27-monitoring-strategy.md) · [runbook 31](runbooks/31-deploy-netdata.md) | ✅ |
| **Cloud telemetry** | Azure Monitor — the Arc-enrolled nodes' metrics and inventory, beside the rest of Azure | [ADR 09](decisions/09-azure-monitor-via-arc.md) | ✅ |
| **Power state** | UPS charge, voltage, load and on-battery events charted in Netdata (`Remote Devices → UPS`) | [ADR 30](decisions/30-ups-nut-graceful-shutdown.md) · [runbook 31](runbooks/31-deploy-netdata.md) | ✅ |
| **Disk health** | Drive health and long self-test results for the NAS arrays, per drive | [research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md) | ✅ |
| **Per-device energy** | Power draw per wall plug, charted in Grafana | [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) · [ADR 26](decisions/26-zigbee-energy-monitoring.md) | 📋 |
| **Logs** | VictoriaLogs — the fleet's logs searchable in one place on the `pve` node, 30d retention | [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) · [ADR 36](decisions/36-log-collector-fluentbit.md) · [runbook 34](runbooks/34-deploy-fluentbit.md) · [runbook 33](runbooks/33-deploy-victorialogs.md) | ✅ |

**Why two tiers**: Arc sees only the nodes enrolled in it, and the Edge appliance and `pve` are never
enrolled — so the management plane (policy, compliance, portal, heartbeat) can never show the whole
fleet. Real-time metrics come from Netdata on **every** LAN node instead.

## What's Next

Planned and in-progress work only, listed in execution order. The backlog lives in
[Issues](https://github.com/jaroslaw-bagnicki/Homelab/issues) and is pulled in here
once it is ready to start — a row leaves the table with the PR that completes it.

**Effort**: ⭐ one session · ⭐⭐ a few sessions · ⭐⭐⭐ multi-week or hardware-gated

### In progress

| Item | Effort | Next step | Refs |
|---|---|---|---|
| **Beetle NAS** | ⭐⭐⭐ | **Phase 1 done** — OMV 8.5 on `nas`, `md0` RAID1 clean + reboot-verified (a failed member was replaced 2026-10-17, [runbook 38](runbooks/38-nas-disk-replacement.md)), fleet-enrolled with the Netdata child and NUT secondary; next: create the share and move the backup target, then retire the ML110 and release `.210` (Memtest86+ and the RTC coin cell stay deferred — [research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md)) | [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) · [ADR 29](decisions/29-nas-backup-target-beetle-m3-omv.md) · [runbook 32](runbooks/32-beetle-m3-omv-setup.md) |
| **Home Assistant VM + LXCs** | ⭐⭐⭐ | VM 210 (HA OS) + LXC 211/212 (Mosquitto, Zigbee2MQTT) on the `pve` node (the base from runbook 28), then point HA's NUT integration at `192.168.2.201` for UPS status + power-loss notifications | [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) · [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85) · [ADR 25](decisions/25-home-assistant-thin-client.md) · [#122](https://github.com/jaroslaw-bagnicki/Homelab/issues/122) |


### Planned

| Item | Effort | Next step | Refs |
|---|---|---|---|
| **Power monitoring (Zigbee/Z2M)** | ⭐⭐ | Zigbee energy plugs → Prometheus, bootstrapped standalone on the M910q (ADR 26 — independent of Home Assistant) — sequenced **before** k3s | [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) · [ADR 26](decisions/26-zigbee-energy-monitoring.md) |
| **YUMI multiboot USB standard** | ⭐ | Author the YUMI ADR (number on landing) + manage-YUMI runbook; de-conflate the Ventoy references | [#107](https://github.com/jaroslaw-bagnicki/Homelab/issues/107) · [research 12](research/12-first-boot-setup.md) |
| **Private CA — proxy TLS issuance** | ⭐⭐ | **Running** — `step-ca` on LXC 215 `ca` serves ACME with a TPM-sealed intermediate, signed offline by a 10-year root ([35 deploy](runbooks/35-deploy-step-ca.md), [36 init/re-sign](runbooks/36-private-ca-init.md)); Caddy on `edge` issues 24 h leaves for `netdata.internal`, `dns.internal`, `logs.internal` and `proxmox.internal` ([runbook 37](runbooks/37-deploy-internal-access-stack.md)); root distributed to all six fleet nodes (`ca_trust`, 2026-10-17; `ca` excluded) and the LAN workstation trusts it ([runbook 39](runbooks/39-trust-private-ca.md)) — phones still to install; DNS is enforced fleet-wide by the `common` role and the served leaves are watched from `edge` ([runbook 37 §5](runbooks/37-deploy-internal-access-stack.md)); next: confirm Caddy's unattended renewal holds every leaf inside the 6 h alert threshold over several days | [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) · [#151](https://github.com/jaroslaw-bagnicki/Homelab/issues/151) · [ADR 38](decisions/38-private-ca-hierarchy-and-custody.md) |

### Held

| Item | Waiting on | Refs |
|---|---|---|
| **Edge Ingress — service migration** | remote-access decision — public ingress is on hold (VPN / Tailscale under consideration), so cloudflared and the public plane are not moved to the Wyse 3040; the LAN Caddy/DNS stack is live ([runbook 37](runbooks/37-deploy-internal-access-stack.md)) | [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) · [#81](https://github.com/jaroslaw-bagnicki/Homelab/issues/81) · [ADR 24](decisions/24-edge-ingress-appliance.md) · [ADR 40](decisions/40-internal-dns-proxy-edge.md) |
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
which runs the NUT server **host-native**, with `upsmon` on `pve`/`lab`/`edge`/`nas`
([ADR 39](decisions/39-nut-host-native.md)).

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
