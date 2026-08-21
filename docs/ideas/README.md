# Ideas

Pre-decision exploration and brainstorming. Unlike `docs/decisions/` (ADRs) which record settled design choices, `docs/ideas/` captures ideas, possibilities, and early-stage research — before a decision is made or an ADR is written.

| # | Idea | Status | Description |
|---|---|---|---|
| 01 | [Homelab NAS](01-nas-backup-target.md) | 🧠 Idea | Budget NAS built from Fujitsu Esprimo Q956 + 2× WD Black 500GB, running OMV (V1 — superseded in practice by idea 03) |
| 02 | [DevContainers for OpenCode with DevPod](02-devcontainers-opencode-k3s.md) | 🧠 Idea | Long-lived, project-isolated OpenCode workspaces declared as Dev Containers, using Docker now and K3s later |
| 03 | [Homelab NAS on ML110 (OMV)](03-nas-backup-target-ml110.md) | 🔨 Implementing | Repurpose retired HP ProLiant ML110 (was FreeNAS) as OMV backup target NAS; Phase 0 inventory in [runbook 22](../runbooks/22-ml110-nas-inventory.md), tracked in [issue #54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) |
| 04 | [Dedicated Edge Device for Cloudflare Tunnel + Caddy](04-edge-device-tunnel-caddy.md) | 🔨 Implementing | Move the homelab's public ingress (`cloudflared` + Caddy) off the M910q onto a low-power edge box — decouple ingress from k3s churn (ADR 22), route to OMV without breaking storage-only scope (ADR 23). Decision: [ADR 24](https://github.com/jaroslaw-bagnicki/Homelab/blob/main/docs/decisions/24-edge-ingress-appliance.md) · runbook 24 · Wyse 3040 acquired 2026-08-13 |
| 05 | [Home Assistant on a Thin Client](05-home-assistant-thin-client.md) | 📋 Planned | Dedicated Home Assistant smart-home node on a thin client (Wyse 5070 / Futro S740) — Home Assistant OS as VM on Proxmox VE, Mosquitto + Zigbee2MQTT in LXC next to it, central home placement for Zigbee coverage. Research: [research 26](../research/26-home-assistant-thin-client.md) · Decision: [ADR 25](../decisions/25-home-assistant-thin-client.md) (Proposed) |
| 06 | [Homelab Energy Monitoring](06-homelab-energy-monitoring.md) | 🧠 Idea | Independent homelab power-consumption monitoring — per-device energy plugs (Zigbee leading candidate, alternatives in research), decoupled from Home Assistant, data to the lab's monitoring stack + AI agent. Details: [research 27](../research/27-zigbee-energy-monitoring.md) |
| 07 | [OPNsense Router on Fujitsu Futro S930](07-opnsense-futro-s930.md) | 🧠 Idea | Dedicated OPNsense firewall/router on a Fujitsu Futro S930 (AMD GX-424CC + AES-NI) with a low-profile Intel i350 multi-port NIC — the lab's first real router/firewall (NGFW, VLANs, VPN, IDS/IPS), between the ISP fiber router and the LAN |

## Lifecycle

1. **🧠 Idea** — initial exploration, hardware research, software comparisons
2. **📋 Planned** — scoped, approved, an ADR is in progress
3. **🔨 Implementing** — ADR accepted, implementation underway
4. **✅ Done** — archived in ADR log and `docs/decisions/`

When an idea matures into a decision, it gets an ADR in `docs/decisions/` and the idea doc moves to "Done" status with a cross-reference to the ADR.
