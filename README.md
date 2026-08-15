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

The homelab runs on a **Lenovo M910q Tiny** managed via **Ansible**, with workloads in
**Docker Compose** today and **Kubernetes (k3s + Azure Arc)** as the destination. Public
access goes through **Cloudflare Tunnel** behind a **Caddy** reverse proxy. See the
[Overview](docs/overview.md) for the current nodes, workloads, and topology, and
[Hardware](docs/hardware.md) for per-node specs.
