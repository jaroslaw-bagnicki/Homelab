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

## TODO / Execution List

> Ordered by dependency — earlier steps must complete before later steps begin.

| # | Task | Depends on | Notes |
|---|---|---|---|
| 1 | **Purchase Lenovo ThinkCentre M910q** | — | i5-7500T / 16 GB / 256 GB — see doc 03 for selection criteria and Allegro search tips |
| 2 | First-boot checklist | ✅ Done | Inspect thermal paste, verify RAM/SATA, check PSU, flash BIOS — see doc 03 |
| 3 | ✅ Install Ubuntu Server + initial setup | ✅ Done | Windows backup, BIOS fix, static IP, SSH, LVM resize, user config — see doc 12 |
| 4 | Base OS hardening | Step 3 (ready) | UFW firewall, fail2ban, unattended-upgrades, SSH key-based auth — advisory ready in doc 12 |
| 5 | Docker + Portainer CE | Step 4 | Install Docker engine, enable auto-start, deploy Portainer |
| 6 | Hermes Agent install + config | Step 5 | ⚠️ Verify install URL against `github.com/nousresearch/hermes-agent` before running — see doc 04 |
| 7 | Cloudflare Tunnel setup | Step 6 | Zero-trust tunnel for public access to web UIs |
| 8 | Backup strategy | Step 7 | Install secondary SATA disk, configure Restic — see doc 10 |
| 9 | Azure Arc enrolment | Step 8 | Register M910q in Azure — use least-privilege SP, see doc 07 |
| 10 | Ollama + Bielik (Phase 2) | Step 9 | Local Polish LLM inference — only after Phase 1 is stable; see doc 08 |

## Research

| # | Document | Topic | Source |
|---|---|---|---|
| 01 | [01-hardware-mini-pc.md](research/01-hardware-mini-pc.md) | Second-hand mini PC shortlist & general guidance | Gemini chat 1 |
| 02 | [02-llm-requirements.md](research/02-llm-requirements.md) | LLM resource requirements & local-vs-API trade-offs | Gemini chat 1 |
| 03 | [03-selected-hardware-m910q.md](research/03-selected-hardware-m910q.md) | M910q Tiny: detailed specs, ports, storage rationale | Gemini chat 2 |
| 04 | [04-hermes-agent-setup.md](research/04-hermes-agent-setup.md) | Hermes Agent install plan, MiniMax M2.7 config, chat UIs | Gemini chat 2 |
| 05 | [05-container-stack.md](research/05-container-stack.md) | Docker Compose → k3s migration path, service catalogue, disk layout, restart policies | Gemini chat 2 |
| 06 | [06-networking-connectivity.md](research/06-networking-connectivity.md) | CGNAT solutions: Cloudflare Tunnels, Tailscale, hybrid proxy | Gemini chat 2 |
| 07 | [07-azure-arc-and-cost.md](research/07-azure-arc-and-cost.md) | Azure Arc enrolment, physical vs cloud cost comparison | Gemini chat 2 |
| 08 | [08-llm-server-hardware.md](research/08-llm-server-hardware.md) | Dedicated LLM server hardware paths; Minisforum X1 Lite selected (Phase 2) | Gemini chat 3 |
| 09 | [09-os-decision.md](research/09-os-decision.md) | OS choice | Research |
| 10 | [10-backup-strategy.md](research/10-backup-strategy.md) | Restic backup to secondary SATA disk, retention, disaster recovery | Research |
| 11 | [11-local-dns-caddy.md](research/11-local-dns-caddy.md) | Local DNS via Caddy, mDNS for `.homelab.local` resolution | Research |
| 12 | [12-first-boot-setup.md](research/12-first-boot-setup.md) | First-boot: backup, BIOS, static IP, SSH, LVM resize, hardening | Gemini chat 4 |

## Gemini Discussions

| # | Link | Docs |
|---|---|---|
| 1 | [Gemini chat 1](https://gemini.google.com/share/076895cbd654) | 01, 02 |
| 2 | [Gemini chat 2](https://gemini.google.com/share/6ea05b934c81) | 03, 04, 05, 06, 07 |
| 3 | [Gemini chat 3](https://gemini.google.com/share/24e2d3af7b59) | 08 |
| 4 | [Gemini chat 4](https://gemini.google.com/share/3bec83a4906e) | 12 |
