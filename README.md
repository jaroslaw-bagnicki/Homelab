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

## What's Next

Ordered by dependency and effort. See [setup/README.md](homelab/setup/README.md) for runbooks.

| # | Workload | Effort | Notes |
|---|---|---|---|
| 5 | **Cloudflare Tunnel** | ⭐ | Remote HTTPS access, needed before monitoring |
| 6 | **Azure Arc** | ⭐ | Register in Azure while it's fresh |
| 7 | **Monitoring** (ELK/Prometheus/Seq) | ⭐⭐⭐ | Needs research — explore options first |
| 8 | **Backup strategy** (Restic) | ⭐⭐ | Protect everything before Hermes Agent |
| 9 | **Hermes Agent** | ⭐⭐⭐ | Most complex — last |
| 10 | **Ollama + Bielik** (Phase 2) | ⭐⭐⭐ | Needs dedicated LLM server hardware |

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

---

## Links

- [Research index](research/README.md)
- [Setup runbooks](setup/README.md)
