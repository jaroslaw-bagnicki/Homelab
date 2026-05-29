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
| First-boot setup | ✅ Done | Windows backup, BIOS fix, static IP, SSH, user config, LVM resize — see doc 12 |
| Base OS hardening | 🔧 In progress | Advisory given (UFW, fail2ban, unattended-upgrades, SSH keys) — see doc 12 |
| LLM / AI stack | 🔍 Research | MiniMax M2.7 (cloud API) via Hermes Agent — see doc 04 |
| Docker services | 🔍 Research | Stack defined — see doc 05 |
| Networking | 🔍 Research | Cloudflare Tunnels + Tailscale; mDNS/Avahi installed — see docs 06, 12 |
| Azure integration | 🔍 Research | Azure Arc onboarding planned — see doc 07 |

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
| 3 | ✅ Install Ubuntu Server + initial setup | ✅ Done | Windows backup, BIOS fix, static IP, SSH, LVM resize, user config — see doc 12 |
| 4 | Base OS hardening | Step 3 (ready) | UFW firewall, fail2ban, unattended-upgrades, SSH key-based auth — advisory ready in doc 12 |
| 5 | Docker + Portainer CE | Step 4 | Install Docker engine, enable auto-start, deploy Portainer — see [2-docker.md](setup/2-docker.md) |
| 6 | Hermes Agent install + config | Step 5 | ⚠️ Verify install URL against `github.com/nousresearch/hermes-agent` before running — see doc 04 |
| 7 | Cloudflare Tunnel setup | Step 6 | Zero-trust tunnel for public access to web UIs |
| 8 | Backup strategy | Step 7 | Install secondary SATA disk, configure Restic — see doc 10 |
| 9 | Azure Arc enrolment | Step 8 | Register M910q in Azure — use least-privilege SP, see doc 07 |
| 10 | Ollama + Bielik (Phase 2) | Step 9 | Local Polish LLM inference — only after Phase 1 is stable; see doc 08 |

## Research

See [research/README.md](research/README.md) for the full document index and Gemini discussion links.

---

## Changelog

| Date | What |
|---|---|
| 2026-05-20 | Research phase started — hardware shortlist, LLM requirements, OS decision |
| 2026-05-24 | M910q selected — ordered on Allegro |
| 2026-05-29 | Initial setup complete — Ubuntu Server 24.04 |
| 2026-05-29 | Docker Engine + Portainer CE deployed and running |
