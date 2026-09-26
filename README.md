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

## The fleet

**Status**: ✅ running · 🔨 in progress · 📋 planned · 🧠 idea

| Node | Role | Status |
|---|---|---|
| **Lab** — Lenovo M910q Tiny (`lab`) | main workload host · Ubuntu 24.04 LTS · Azure Arc · Docker → k3s | ✅ |
| **Proxmox VE** — Dell Wyse 5070 (`pve`) | virtualisation host — smart-home + always-on services, Netdata Parent | 🔨 |
| **Beetle NAS** — Wincor Beetle M-III (`nas`) | OMV 8.5 backup target · `md0` RAID1 · Netdata child + NUT secondary | 🔨 |
| **OMV NAS** — HP ProLiant ML110 | incumbent backup target, retiring once the Beetle's share is live | ✅ |
| **Edge Ingress** — Dell Wyse 3040 (`edge`) | dedicated public ingress — `cloudflared` + Caddy | 🔨 |
| **OPNsense Router** — Fujitsu Futro S930 | LAN edge router / firewall | 📋 |
| **LLM server** — Minisforum AI X1 | local LLM inference (Phase 2) | 🧠 |
| **Cloudlab VPS** — Contabo | disposable staging for Ansible + hosted workloads | ✅ |

Workloads run in **Docker Compose** today with **Kubernetes (k3s + Azure Arc)** as the
destination; public access is **Cloudflare Tunnel** behind a **Caddy** reverse proxy; LAN
services are **TLS-only**; and a shared-rail **UPS under NUT** stops the fleet in order when the
battery runs down (measured **52 min 53 s** at the ~80 W fleet in a real-outage drill). Per-node
specs live in [Hardware](docs/hardware.md); topology and roadmap in [Overview](docs/overview.md).

## Where the project is

**In flight:** moving `cloudflared` + Caddy onto the dedicated edge appliance · finishing the
Beetle's backup share so the ML110 can retire · Home Assistant OS plus Mosquitto/Zigbee2MQTT
LXCs on the `pve` node.

**Next up:** Zigbee energy monitoring into Prometheus, then the **k3s migration** that takes
workloads off Docker Compose. Sequencing lives on the [Overview](docs/overview.md) board; what
shipped lives in the [Changelog](CHANGELOG.md).

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
