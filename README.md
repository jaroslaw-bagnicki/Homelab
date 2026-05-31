# Homelab

> **Have fun. Sharpen the saw. Experiment with AI workloads.**

A home lab server built on a second-hand mini PC, running Ubuntu Server as the base OS. This is my sandbox — a place to tinker with technologies I don't use at work, self-host AI agents, and keep learning for the joy of it.

## Goals

- 🎮 **Have fun** — tinkering for the joy of it, no deadlines
- 🔧 **Sharpen the saw** — supplement and extend my Operations and DevOps expertise by running infrastructure hands-on
- 🤖 **Experiment with AI workloads** — run Hermes Agent with cloud/hybrid LLMs, and eventually local inference on dedicated hardware

## Selected Hardware

**Lenovo ThinkCentre M910q Tiny** — i5-7500T / 16 GB DDR4 / 256 GB SSD  
4C/4T, 35 W TDP, Intel HD 630 with QuickSync, ~7–10 W idle, ~150 EUR second-hand.

---

## What's Done

| Date | Workload | Effort | # | Notes |
|---|---|---|---|---|
| 2026‑05‑20 | Research | ⭐⭐⭐ | — | Hardware, LLM, OS decisions |
| 2026‑05‑24 | Purchase | ⭐ | — | M910q ordered on Allegro |
| 2026‑05‑29 | Base setup | ⭐⭐ | [1](runbooks/1-init.md) | Ubuntu, static IP, SSH, LVM, mDNS, hardening |
| 2026‑05‑29 | Docker | ⭐⭐ | [2](runbooks/2-docker.md) | Engine + Portainer CE |
| 2026‑05‑29 | DNSMasq | ⭐ | [3](runbooks/3-dns.md) | `*.home` resolution |
| 2026‑05‑29 | Caddy | ⭐ | [4](runbooks/4-caddy.md) | Reverse proxy with auto-TLS |
| 2026‑05‑30 | Cloudflare Tunnel | ⭐⭐ | [5](runbooks/5-cloudflare-tunnel.md) | Remote HTTPS access via custom domain |
| 2026‑05‑30 | Azure Arc | ⭐⭐ | [6](runbooks/6-azure-arc.md) | Hybrid server enrollment, cert-based auth |
| 2026‑05‑31 | GHCR in Portainer | ⭐ | [2a](runbooks/2a-ghcr-portainer.md) | GitHub Container Registry access |
| 2026‑05‑31 | Hello World demo | ⭐ | [4a](runbooks/4a-hello-world.md) | Reverse proxy demo via Caddy + Cloudflare |

---

## What's Next

| # | Workload | Effort | Notes |
|---|---|---|---|
| 6a | **Monitoring** (Azure Monitor) | ⭐ | Metrics and logs via Arc — see [runbook](runbooks/6a-azure-monitor.md) |
| 7 | **Backup strategy** (Restic) | ⭐⭐ | Protect everything before Hermes Agent |
| 8 | **Hermes Agent** | ⭐⭐⭐ | Most complex — last |
| 9 | **SQL Server** | ⭐⭐ | Developer Edition in Docker — see [runbook](runbooks/9-mssql-dev.md) |
| 10 | **Gitea** | ⭐⭐ | Self-hosted Git with web UI for personal repos |
| - | **Ollama + Bielik** (Phase 2) | ⭐⭐⭐ | Needs dedicated LLM server hardware |

---

## Links

- [Research index](research/README.md)
- [Runbooks](runbooks/README.md)
