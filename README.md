# Homelab

> **Have fun. Sharpen the saw. Experiment with AI workloads.**

A small fleet of second-hand mini PCs and thin clients, running Linux and managed entirely
as code — **Ansible** for declarative host configuration, a documented decision log for every
design choice, and runbooks for every procedure. A disposable Contabo Cloud VPS is the
staging ground where Ansible changes are proven before they touch hardware.

This is my sandbox — a place to tinker with technologies I don't use at work,
self-host AI agents, and keep learning for the joy of it.

---

## Goals

- 🎮 **Have fun** — tinkering for the joy of it, no deadlines
- 🔧 **Sharpen the saw** — supplement and extend my Operations and DevOps expertise by running infrastructure hands-on
- 🤖 **Experiment with AI workloads** — run Hermes Agent with cloud/hybrid LLMs, and eventually local inference on dedicated hardware

## Tech stack

**Ansible** provisions every host; workloads run in **Docker Compose** today with
**Kubernetes (k3s + Azure Arc)** as the destination. Public access is **Cloudflare Tunnel**
behind a **Caddy** reverse proxy, LAN services are **TLS-only**, a shared-rail **UPS under NUT**
shuts the fleet down in order when the battery runs low, and **Netdata** aggregates the fleet's
metrics. A disposable **Contabo VPS** hosts the staging workloads.

The nodes — workload host, Proxmox VE smart-home node, OMV backup NAS, dedicated ingress
appliance, router — are listed with their current status, workloads and roadmap on
[Overview](docs/overview.md); per-node specs are in [Hardware](docs/hardware.md).

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
