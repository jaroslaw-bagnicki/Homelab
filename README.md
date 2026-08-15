# Homelab

> **Have fun. Sharpen the saw. Experiment with AI workloads.**

A home lab server built on a second-hand mini PC, running Linux, managed via
**Ansible** for declarative, GitOps-style host configuration. A disposable
Contabo Cloud VPS playground is used to develop and test Ansible playbooks
before they touch the physical hardware.

This is my sandbox — a place to tinker with technologies I don't use at work,
self-host AI agents, and keep learning for the joy of it.

---

## Explore

| Area | Description |
|---|---|
| [Overview](docs/overview.md) | Homelab at a glance — nodes, workloads, topology |
| [Hardware](docs/hardware.md) | Per-node hardware inventory + network appliances |
| [Ideas](docs/ideas/README.md) | Pre-decision brainstorming — possibilities and early-stage exploration |
| [Research](docs/research/README.md) | Exploratory research — topic investigations, comparisons, trade-offs |
| [Decision log](docs/decisions/README.md) | Architecture Decision Records (ADRs) — settled design rationale, source of truth |
| [Runbooks](docs/runbooks/README.md) | Step-by-step implementation guides |
| [Workloads](docs/workloads.md) | Self-contained Ansible workload recipes |
| [Changelog](CHANGELOG.md) | Notable changes, newest first |

## Goals

- 🎮 **Have fun** — tinkering for the joy of it, no deadlines
- 🔧 **Sharpen the saw** — supplement and extend my Operations and DevOps expertise by running infrastructure hands-on
- 🤖 **Experiment with AI workloads** — run Hermes Agent with cloud/hybrid LLMs, and eventually local inference on dedicated hardware

## Tech Stack

The physical server is a **[Lenovo ThinkCentre M910q Tiny](docs/decisions/01-hardware-selection-m910q.md)** (i5-7500T, 16 GB RAM).
It will be rebuilt from scratch on **[Ubuntu 24.04 LTS](docs/decisions/05-os-decision-ubuntu-server.md)**, managed entirely via
**[Ansible](docs/decisions/10-ansible-host-config.md)** playbooks — developed and tested on a disposable **[Contabo Cloud VPS 10](docs/decisions/13-cloudlab-staging.md)** before touching the hardware.

Applications currently run in **Docker Compose**; the migration to **Kubernetes (k3s + Azure Arc)** is the destination per [ADR 22](docs/decisions/22-k3s-arc-homelab.md). The server
is enrolled in **[Azure Arc](docs/decisions/04-hybrid-cloud-azure-arc.md)** for cloud-side monitoring and policy, and exposed
to the internet via **[Cloudflare Tunnel](docs/decisions/08-remote-access-cloudflare-tunnel.md)** behind a **[Caddy](docs/decisions/07-reverse-proxy-caddy.md)** reverse proxy.

The **network layer** terminates homelab gear on a **TP-Link TL-SG108E** access switch (`192.168.2.230`) with a single uplink to the office Tenda Nova mesh — one office drop → multiple wired devices. Static reservations in `192.168.2.200+`: Lenovo M910q Homelab `.200`, HP ML110 OMV NAS `.210`. See [research 24](docs/research/24-network-topology-design.md) and [runbook 21](docs/runbooks/21-tl-sg108e-switch.md).

---

## Project Structure

| Folder | Purpose |
|---|---|
| [`ansible/`](ansible/README.md) | Host provisioning — playbooks, roles (common, security, azure_arc, docker_host, docker_services, workloads), inventory |
| [`bicep/`](bicep/README.md) | Cloud-side IaC — Log Analytics, DCR, AMA extensions, Key Vault |
| [`scripts/`](scripts/) | Standalone PowerShell utilities (SSH key management, Arc client secrets, OpenCode backup) |

Ansible runs first on the bare host (OS config, Docker, Arc agent). Bicep deploys cloud resources after Arc enrolment. The decision log is the source of truth for design rationale. Runbooks capture implementation steps. Research docs capture exploratory context that predates settled decisions. Ideas capture possibilities before a decision is made.

---

## Recent Work

Completed work and notable changes are tracked in the [changelog](CHANGELOG.md).
