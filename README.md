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

| Date | Workload | Effort | Notes |
|---|---|---|---|
| 2026‑05‑20 | Research | ⭐⭐⭐ | Hardware, LLM, OS decisions |
| 2026‑05‑24 | Purchase | ⭐ | M910q ordered on Allegro |
| 2026‑05‑29 | Base setup | ⭐⭐ | Ubuntu, static IP, SSH, LVM, mDNS, hardening |
| 2026‑05‑29 | Docker | ⭐⭐ | Engine + Portainer CE |
| 2026‑05‑29 | DNSMasq | ⭐ | `*.home` resolution |
| 2026‑05‑29 | Caddy | ⭐ | Reverse proxy with auto-TLS |
| 2026‑05‑30 | Cloudflare Tunnel | ⭐⭐ | Remote HTTPS access via custom domain |
| 2026‑05‑30 | Azure Arc | ⭐⭐ | Hybrid server enrollment, cert-based auth |

---

## What's Next

| # | Workload | Effort | Notes |
|---|---|---|---|
| 6a | **Monitoring** (Azure Monitor) | ⭐ | Metrics and logs via Arc — see [runbook](setup/6a-azure-monitor.md) |
| 6 | **Backup strategy** (Restic) | ⭐⭐ | Protect everything before Hermes Agent |
| 2a | **GHCR in Portainer** | ⭐ | GitHub Container Registry access — see [runbook](setup/2a-ghcr-portainer.md) |
| 7 | **Hermes Agent** | ⭐⭐⭐ | Most complex — last |
| 8 | **Gitea** | ⭐ | Self-hosted Git with web UI for personal repos |
| 9 | **Ollama + Bielik** (Phase 2) | ⭐⭐⭐ | Needs dedicated LLM server hardware |

---

## Links

- [Research index](research/README.md)
- [Setup runbooks](setup/README.md)
