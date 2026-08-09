# Ideas

Pre-decision exploration and brainstorming. Unlike `docs/decisions/` (ADRs) which record settled design choices, `docs/ideas/` captures ideas, possibilities, and early-stage research — before a decision is made or an ADR is written.

| # | Idea | Status | Description |
|---|---|---|---|
| 01 | [Homelab NAS](01-nas-backup-target.md) | 🧠 Idea | Budget NAS built from Fujitsu Esprimo Q956 + 2× WD Black 500GB, running OMV (V1 — superseded in practice by idea 03) |
| 02 | [DevContainers for OpenCode with DevPod](02-devcontainers-opencode-k3s.md) | 🧠 Idea | Long-lived, project-isolated OpenCode workspaces declared as Dev Containers, using Docker now and K3s later |
| 03 | [Homelab NAS on ML110 (OMV)](03-nas-backup-target-ml110.md) | 📋 Planned | Repurpose retired HP ProLiant ML110 (was FreeNAS) as OMV backup target NAS; Phase 0 inventory in [runbook 21](../runbooks/21-ml110-nas-inventory.md), tracked in [issue #54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) |
| 04 | [Dedicated Edge Device for Cloudflare Tunnel + Caddy](04-edge-device-tunnel-caddy.md) | 🧠 Idea | Move the homelab's public ingress (`cloudflared` + Caddy) off the M910q onto a low-power edge box (e.g. RPi) — decouple ingress from k3s churn (ADR 22), route to OMV without breaking storage-only scope (ADR 23) |

## Lifecycle

1. **🧠 Idea** — initial exploration, hardware research, software comparisons
2. **📋 Planned** — scoped, approved, an ADR is in progress
3. **🔨 Implementing** — ADR accepted, implementation underway
4. **✅ Done** — archived in ADR log and `docs/decisions/`

When an idea matures into a decision, it gets an ADR in `docs/decisions/` and the idea doc moves to "Done" status with a cross-reference to the ADR.
