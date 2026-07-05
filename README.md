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

The physical server is a **[Lenovo ThinkCentre M910q Tiny](docs/decisions/01-hardware-selection-m910q.md)** (i5-7500T, 16 GB RAM).
It will be rebuilt from scratch on **[Ubuntu 24.04 LTS](docs/decisions/05-os-decision-ubuntu-server.md)**, managed entirely via
**[Ansible](docs/decisions/10-ansible-host-config.md)** playbooks — developed and tested on a disposable **[Contabo Cloud VPS 10](docs/decisions/13-vps-playground.md)** before touching the hardware.

Applications run in **[Docker Compose](docs/decisions/03-container-strategy.md)** with a future path to **k3s**. The server
is enrolled in **[Azure Arc](docs/decisions/04-hybrid-cloud-azure-arc.md)** for cloud-side monitoring and policy, and exposed
to the internet via **[Cloudflare Tunnel](docs/decisions/08-remote-access-cloudflare-tunnel.md)** behind a **[Caddy](docs/decisions/07-reverse-proxy-caddy.md)** reverse proxy.

---

## Project Structure

| Folder | Purpose |
|---|---|
| [`ansible/`](ansible/README.md) | Host provisioning — playbooks, roles (common, security, azure_arc, docker_host, docker_services), inventory |
| [`bicep/`](bicep/README.md) | Cloud-side IaC — Log Analytics, DCR, AMA extensions, Key Vault |
| [`docs/decisions/`](docs/decisions/README.md) | Architecture Decision Records (ADRs) — design rationale, settled decisions |
| [`docs/research/`](docs/research/README.md) | Exploratory research — topic investigations, comparisons, trade-off analyses |
| [`docs/runbooks/`](docs/runbooks/README.md) | Step-by-step implementation guides referenced from the progress table |
| [`scripts/`](scripts/) | Standalone PowerShell utilities (SSH key management, Arc client secrets) |

Ansible runs first on the bare host (OS config, Docker, Arc agent). Bicep deploys cloud resources after Arc enrolment. The decision log is the source of truth for design rationale. Runbooks capture implementation steps. Research docs capture exploratory context that predates settled decisions.

---

## What's Done

| Date | Workload | Effort | # | Notes |
|---|---|---|---|---|
| 2026‑05‑20 | Research | ⭐⭐⭐ | — | Hardware, LLM, OS decisions |
| 2026‑05‑24 | Purchase | ⭐ | — | M910q ordered on Allegro |
| 2026‑05‑29 | Base setup | ⭐⭐ | [1](docs/runbooks/1-init.md) | Ubuntu, static IP, SSH, LVM, mDNS, hardening |
| 2026‑05‑29 | Docker | ⭐⭐ | [2](docs/runbooks/2-docker.md) | Engine + Portainer CE |
| 2026‑05‑29 | DNSMasq | ⭐ | [3](docs/runbooks/3-dns.md) | `*.home` resolution |
| 2026‑05‑29 | Caddy | ⭐ | [4](docs/runbooks/4-caddy.md) | Reverse proxy with auto-TLS |
| 2026‑05‑30 | Cloudflare Tunnel | ⭐⭐ | [5](docs/runbooks/5-cloudflare-tunnel.md) | Remote HTTPS access via custom domain |
| 2026‑05‑30 | Azure Arc | ⭐⭐ | [6](docs/runbooks/6-azure-arc.md) | Hybrid server enrollment, cert-based auth |
| 2026‑05‑31 | GHCR in Portainer | ⭐ | [2a](docs/runbooks/2a-ghcr-portainer.md) | GitHub Container Registry access |
| 2026‑05‑31 | Hello World demo | ⭐ | [4a](docs/runbooks/4a-hello-world.md) | Reverse proxy demo via Caddy + Cloudflare |
| 2026‑06‑16 | Decision log | ⭐ | [#7](https://github.com/jaroslaw-bagnicki/Homelab/issues/7) | ADR log in MADR format — see [docs/decisions/](docs/decisions/) |
| 2026‑06‑17 | VPS playground | ⭐⭐ | [10](docs/runbooks/10-vps-playground.md) | Contabo Cloud VPS 10 as Ansible dev/test sandbox — see [ADR 13](docs/decisions/13-vps-playground.md) |
| 2026‑06‑20 | Key Vault | ⭐ | [bicep/](bicep/README.md) | RBAC-only vault `homelab-{suffix}-kv` provisioned alongside Bicep infrastructure — see [#6](https://github.com/jaroslaw-bagnicki/Homelab/issues/6) |
| 2026‑06‑20 | Ansible playbooks | ⭐⭐⭐ | [ansible/](ansible/README.md) | common, security, azure_arc, docker_host roles developed & tested on cloudlab — see [#9](https://github.com/jaroslaw-bagnicki/Homelab/issues/9) |
| 2026‑06‑21 | Azure Monitor | ⭐⭐ | [6a](docs/runbooks/6a-azure-monitor.md) | VM Insights working on cloudlab via `\VmInsights\DetailedMetrics` meta-counter — Bicep-managed |
| 2026‑06‑28 | Codespaces SP | ⭐ | [14](docs/runbooks/14-gh-codespaces-sp-for-homelab.md) | `homelab-codespaces-sp` provisioned, stored in `homelab-bysxdb-kv`, consumed via Codespaces repo secrets — enables Azure MCP for Opencode eval — see [ADR 16](docs/decisions/16-gh-codespaces-sp-for-homelab.md) |
| 2026‑06‑28 | Opencode adoption | ⭐ | [15](docs/runbooks/15-opencode-session-persistence.md) | OpenCode runtime data persisted via symlinks to `/workspaces/.opencode` (sibling of repo) and backed up on-demand to `homelabcloud5/opencode-backups` — survives both Dev Container rebuilds and Codespace deletion |
| 2026‑07‑04 | Docker Services role | ⭐⭐ | [16](docs/runbooks/16-docker-services-ansible-role.md) | Ansible `docker_services` role — deploys Portainer, Caddy, and Hello World on Cloudlab via `docker_compose_v2` — see [#14](https://github.com/jaroslaw-bagnicki/Homelab/issues/14) |
| 2026‑07‑05 | Cloudflare Tunnel on Cloudlab | ⭐⭐ | [16](docs/runbooks/16-docker-services-ansible-role.md) | `cloudflared` added to `docker_services` role — HTTPS-only origin via CF Tunnel + Cloudflare Origin CA cert (SANs `*.ctb.cloud5.ovh` + `ctb.cloud5.ovh`); CF Tunnel public hostnames `ctb.cloud5.ovh` and `hello.ctb.cloud5.ovh` configured per-service (free tier does not support multi-level wildcards) — see [ADR 19](docs/decisions/19-cloudflare-tunnel-https-origin.md) and [#25](https://github.com/jaroslaw-bagnicki/Homelab/issues/25) |

---

## What's Next

| # | Workload | Effort | Notes |
|---|---|---|---|
| [#13](https://github.com/jaroslaw-bagnicki/Homelab/issues/13) | **Restic backup** (redo) | ⭐⭐ | Daily snapshots to Azure Blob Storage — see [runbook](docs/runbooks/7-restic-backup.md) |
|  | **Hermes Agent** | ⭐⭐⭐ | Most complex — last |
|  | **SQL Server** | ⭐⭐ | Developer Edition in Docker — see [runbook](docs/runbooks/9-mssql-dev.md) |
|  | **Gitea** | ⭐⭐ | Self-hosted Git with web UI for personal repos |
| - | **Ollama + Bielik** (Phase 2) | ⭐⭐⭐ | Needs dedicated LLM server hardware |

---

## Links

- [Research index](docs/research/README.md)
- [Decision log](docs/decisions/README.md)
- [Ansible playbooks & roles](ansible/README.md)
- [Bicep infrastructure](bicep/README.md)
- [Runbooks](docs/runbooks/README.md)
