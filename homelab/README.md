# Homelab

A home lab server built on a second-hand mini PC, running Ubuntu Server as the base OS. Primary goal is to self-host AI agents and supporting services without relying on cloud compute for day-to-day workloads.

## Goals

- Run an AI agent (Hermes Agent) locally — lightweight LLM inference on CPU/RAM, or hybrid via cloud API
- Self-host containerised services (Docker): automation, monitoring, personal tools
- Low power consumption for 24/7 operation (target idle ≤10 W)
- Budget-conscious: second-hand hardware from Allegro (Polish resale market)

## Selected Hardware

**Lenovo ThinkCentre M910q Tiny** — i5-7500T / 16 GB DDR4 / 256 GB SSD  
4C/4T, 35 W TDP, Intel HD 630 with QuickSync, ~7–10 W idle, ~400–550 PLN second-hand.

Full specs: [research/03-selected-hardware-m910q.md](research/03-selected-hardware-m910q.md)

## Status

| Area | Status | Notes |
|---|---|---|
| Hardware selection | ✅ Selected | Lenovo M910q Tiny — see doc 03 |
| OS & base stack | ✅ Installed | Ubuntu Server 24.04 LTS installed, LVM resized to full 232 GB — see doc 12 |
| First-boot setup | ✅ Done | Windows backup, BIOS fix, static IP, SSH, LVM resize — see doc 12 |
| Base OS hardening | ✅ Done | UFW, fail2ban, unattended-upgrades, SSH keys |
| Docker + Portainer CE | ✅ Done | Docker Engine + Portainer CE deployed |
| Local DNS | ✅ Done | DNSMasq resolving `*.home` |
| Caddy reverse proxy | ✅ Done | Auto-TLS for `*.home` services |
| LLM / AI stack | 🔍 Research | MiniMax M2.7 (cloud API) via Hermes Agent — see doc 04 |
| Cloudflare Tunnel | 🔍 Planned | Zero-trust tunnel for remote access |
| Azure integration | 🔍 Planned | Azure Arc onboarding — see doc 07 |

## Setup Runbooks

Step-by-step guides in [`setup/`](setup/):

| # | Runbook | Topic |
|---|---|---|
| 1 | [1-init.md](setup/1-init.md) | Ubuntu install, static IP, SSH, LVM resize, mDNS, SSH key, hardening |
| 2 | [2-docker.md](setup/2-docker.md) | Docker Engine + Portainer CE |
| 3 | [3-dns.md](setup/3-dns.md) | Local DNS (DNSMasq) |
| 4 | [4-caddy.md](setup/4-caddy.md) | Caddy reverse proxy with TLS |

## TODO / Execution List

> Ordered by dependency — earlier steps must complete before later steps begin.

| # | Task | Depends on | Notes |
|---|---|---|---|
| 1 | **Purchase Lenovo ThinkCentre M910q** | — | i5-7500T / 16 GB / 256 GB — see doc 03 for selection criteria and Allegro search tips |
| 2 | First-boot checklist | ✅ Done | Inspect thermal paste, verify RAM/SATA, check PSU, flash BIOS — see doc 03 |
| 3 | ✅ Ubuntu Server + initial setup | ✅ Done | Static IP, SSH, LVM resize, mDNS, hardening — see [1-init.md](setup/1-init.md) |
| 4 | ✅ Base OS hardening | ✅ Done | UFW, fail2ban, unattended-upgrades, SSH keys |
| 5 | ✅ Docker + Portainer CE | ✅ Done | See [2-docker.md](setup/2-docker.md) |
| 6 | ✅ Local DNS (DNSMasq) | ✅ Done | `*.home` resolution — see [3-dns.md](setup/3-dns.md) |
| 7 | ✅ Caddy reverse proxy | ✅ Done | Auto-TLS for `*.home` — see [4-caddy.md](setup/4-caddy.md) |
| 8 | Cloudflare Tunnel setup | Step 7 | Zero-trust tunnel for public access |
| 8 | Backup strategy | Step 7 | Install secondary SATA disk, configure Restic — see doc 10 |
| 9 | Azure Arc enrolment | Step 8 | Register M910q in Azure — use least-privilege SP, see doc 07 |
| 10 | Ollama + Bielik (Phase 2) | Step 9 | Local Polish LLM inference — only after Phase 1 is stable; see doc 08 |

## Research

See [research/README.md](research/README.md) for the full document index and Gemini discussion links.
---

## What's Next

Ordered by dependency and effort. Runbooks in [`setup/`](setup/):

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

| Date | Workload | Effort | Notes | Link |
|---|---|---|---|---|
| 2026-05-20 | Research | ⭐⭐⭐ | Hardware, LLM, OS decisions | [research/](research/) |
| 2026-05-24 | Purchase | ⭐ | M910q ordered on Allegro | — |
| 2026-05-29 | Base setup | ⭐⭐ | Ubuntu, static IP, SSH, LVM, mDNS, hardening | [1-init.md](setup/1-init.md) |
| 2026-05-29 | Docker | ⭐⭐ | Engine + Portainer CE | [2-docker.md](setup/2-docker.md) |
| 2026-05-29 | DNSMasq | ⭐ | `*.home` resolution | [3-dns.md](setup/3-dns.md) |
| 2026-05-29 | Caddy | ⭐ | Reverse proxy with auto-TLS | [4-caddy.md](setup/4-caddy.md) |
