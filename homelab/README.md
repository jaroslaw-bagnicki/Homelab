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
| OS & base stack | ⬜ Not started | Ubuntu Server 24.04 LTS planned |
| LLM / AI stack | 🔍 Research | MiniMax M2.7 (cloud API) via Hermes Agent — see doc 04 |
| Docker services | 🔍 Research | Stack defined — see doc 05 |
| Networking | 🔍 Research | Cloudflare Tunnels + Tailscale — see doc 06 |
| Azure integration | 🔍 Research | Azure Arc onboarding planned — see doc 07 |

## Research

| # | Document | Topic | Source |
|---|---|---|---|
| 01 | [01-hardware-mini-pc.md](research/01-hardware-mini-pc.md) | Second-hand mini PC shortlist & general guidance | Gemini chat 1 |
| 02 | [02-llm-requirements.md](research/02-llm-requirements.md) | LLM resource requirements & local-vs-API trade-offs | Gemini chat 1 |
| 03 | [03-selected-hardware-m910q.md](research/03-selected-hardware-m910q.md) | M910q Tiny: detailed specs, ports, storage rationale | Gemini chat 2 |
| 04 | [04-hermes-agent-setup.md](research/04-hermes-agent-setup.md) | Hermes Agent install plan, MiniMax M2.7 config, chat UIs | Gemini chat 2 |
| 05 | [05-docker-homelab-stack.md](research/05-docker-homelab-stack.md) | Docker Compose service catalogue, disk layout, restart policies | Gemini chat 2 |
| 06 | [06-networking-connectivity.md](research/06-networking-connectivity.md) | CGNAT solutions: Cloudflare Tunnels, Tailscale, hybrid proxy | Gemini chat 2 |
| 07 | [07-azure-arc-and-cost.md](research/07-azure-arc-and-cost.md) | Azure Arc enrolment, physical vs cloud cost comparison | Gemini chat 2 |
| 08 | [08-llm-server-hardware.md](research/08-llm-server-hardware.md) | Homelab use cases, Bielik Polish LLM, dedicated LLM server hardware paths (AMD APU / Apple Silicon / GPU), Minisforum AI X1 analysis | Gemini chat 3 |
