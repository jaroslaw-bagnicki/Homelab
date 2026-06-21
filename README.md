# Homelab

> **Have fun. Sharpen the saw. Experiment with AI workloads.**

A home lab server built on a second-hand mini PC, running Linux server, with a planned
clean rebuild managed via **Ansible** for declarative, GitOps-style host
configuration. A disposable VPS playground
serves as a safe playground for developing Ansible playbooks before applying
them to the physical hardware.

This is my sandbox — a place to tinker with technologies I don't use at work,
self-host AI agents, and keep learning for the joy of it.

Key design decisions are recorded in the [decision log](docs/decisions/README.md).

## Goals

- 🎮 **Have fun** — tinkering for the joy of it, no deadlines
- 🔧 **Sharpen the saw** — supplement and extend my Operations and DevOps expertise by running infrastructure hands-on
- 🤖 **Experiment with AI workloads** — run Hermes Agent with cloud/hybrid LLMs, and eventually local inference on dedicated hardware

## Tech Stack

The physical server is a **[Lenovo ThinkCentre M910q Tiny](docs/decisions/260520-01-hardware-selection-m910q.md)** (i5-7500T, 16 GB RAM).
It will be rebuilt from scratch on **[Ubuntu 24.04 LTS](docs/decisions/260524-05-os-decision-ubuntu-server.md)**, managed entirely via
**[Ansible](docs/decisions/260613-10-ansible-host-config.md)** playbooks — developed and tested on a disposable **[Contabo Cloud VPS 10](docs/decisions/260616-13-vps-playground.md)** before touching the hardware.

Applications run in **[Docker Compose](docs/decisions/260524-03-container-strategy.md)** with a future path to **k3s**. The server
is enrolled in **[Azure Arc](docs/decisions/260524-04-hybrid-cloud-azure-arc.md)** for cloud-side monitoring and policy, and exposed
to the internet via **[Cloudflare Tunnel](docs/decisions/260530-08-remote-access-cloudflare-tunnel.md)** behind a **[Caddy](docs/decisions/260529-07-reverse-proxy-caddy.md)** reverse proxy.

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
| 2026‑06‑13 | Restic backup | ⭐⭐ | [7](runbooks/7-restic-backup.md) | Daily snapshots to Azure Blob Storage |
| 2026‑06‑16 | Decision log | ⭐ | [#7](https://github.com/jaroslaw-bagnicki/Homelab/issues/7) | ADR log in MADR format — see [docs/decisions/](docs/decisions/) |
| 2026‑06‑17 | VPS playground | ⭐⭐ | [10](runbooks/10-vps-playground.md) | Contabo Cloud VPS 10 as Ansible dev/test sandbox — see [ADR 13](docs/decisions/260616-13-vps-playground.md) |
| 2026‑06‑20 | Ansible playbooks | ⭐⭐⭐ | [ansible/](ansible/README.md) | common, security, azure_arc, docker_host roles developed & tested on cloudlab — see [#9](https://github.com/jaroslaw-bagnicki/Homelab/issues/9) |
| 2026‑06‑21 | Azure Monitor | ⭐⭐ | [6a](runbooks/6a-azure-monitor.md) | VM Insights working on cloudlab via `\VmInsights\DetailedMetrics` meta-counter — Bicep-managed |

---

## What's Next

| # | Workload | Effort | Notes |
|---|---|---|---|
| 7 | **Hermes Agent** | ⭐⭐⭐ | Most complex — last |
| 8 | **Key Vault** | ⭐ | Central secret storage for homelab — see [#6](https://github.com/jaroslaw-bagnicki/Homelab/issues/6) |
| 9 | **SQL Server** | ⭐⭐ | Developer Edition in Docker — see [runbook](runbooks/9-mssql-dev.md) |
| 10 | **Gitea** | ⭐⭐ | Self-hosted Git with web UI for personal repos |
| - | **Ollama + Bielik** (Phase 2) | ⭐⭐⭐ | Needs dedicated LLM server hardware |

---

## Links

- [Research index](docs/research/README.md)
- [Decision log](docs/decisions/README.md)
- [Ansible playbooks & roles](ansible/README.md)
- [Bicep infrastructure](bicep/README.md)
- [Runbooks](runbooks/README.md)
