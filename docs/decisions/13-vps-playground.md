# Use Contabo Cloud VPS 10 as Ansible Playground for Homelab

**Date:** 2026-06-16  
**Status:** Implemented

---

## Context

The homelab server (Lenovo ThinkCentre M910q Tiny, Ubuntu 24.04 LTS) needs to be
**rebuilt from scratch** — downgrading from Ubuntu 26.x to 24.04 LTS and adopting
**Ansible** for declarative, GitOps-style host configuration management (see
[research 13](research/13-ansible-adoption.md)). Applying untested Ansible
playbooks directly to the production homelab risks downtime, misconfiguration,
and data loss.

A **disposable, low-cost VPS** is needed as a safe playground — a staging
environment where Ansible playbooks can be developed, tested, and hardened
before being applied to the physical server.

Requirements for the playground:

- **2–4 vCPU, 8 GB RAM** — matches or exceeds the homelab spec to surface
  performance regressions
- **Public IPv4** — required for Ansible inventory connectivity and
  Azure Arc enrolment testing
- **EU-hosted** — low latency from Poland, GDPR-aligned
- **Ansible-friendly** — clean REST API for provisioning and teardown
- **Low fixed cost** — the playground will run frequently enough that
  a fixed subscription is acceptable

## Decision

**Use Contabo Cloud VPS 10 (4 vCPU, 8 GB RAM, 75 GB NVMe, €5.50/mo) as the
Ansible playground VPS, managed via a fixed-monthly subscription.**

At €5.50/mo it's **€3.49 cheaper** than the closest Hetzner equivalent (CX33
at €8.99/mo). The break-even where Hetzner's hourly billing would win is
~350 h/mo — well above realistic playground usage. Provisioning is automated
via Contabo's `cntb` CLI with Cloud-Init; post-provisioning config is Ansible.

## Consequences

**Positive:**

- **Lowest fixed cost** — €5.50/mo beats every equivalent VPS from competitors
- **Generous storage** — 75 GB NVMe or 150 GB SSD with unlimited traffic
- **Simple model** — fixed subscription, no hourly tracking or snapshot management
- **Always available** — SSH in and work immediately, no spin-up delay

**Negative:**

- **No hourly billing** — full €5.50/mo charged regardless of uptime
- **Overselling risk** — variable disk I/O under load could mask timing issues
- **200 Mbit/s port** — slower than Hetzner; noticeable during large package installs
- **No native Ansible collection** — requires wrapping `cntb` CLI via Ansible's
  `command` module

### Alternatives Considered

**Hetzner CX33** (€8.99/mo, €0.0144/h). Better Ansible integration and stable
CPU, but 63% more expensive on fixed subscription. Hourly billing only wins
below ~60 h/mo usage.

**Netcup VPS 1000 G11** (~€6.30/mo) — more expensive than Contabo with no
compensating advantage.

**Scaleway / OVHcloud** — both cost more on equivalent specs; Scaleway's
Block Storage alone exceeds Contabo's full subscription cost.

**Local VM on homelab** — defeats the purpose; the playground must be fully
separate and nuke-able.

---

**References:**
- [Research 15: VPS Selection](research/15-vps-selection.md) — detailed provider comparison, corrected pricing tables, and analysis
- [Research 13: Ansible Adoption](research/13-ansible-adoption.md) — Ansible strategy for the homelab
- [ADR 4: Hybrid Cloud Strategy](04-hybrid-cloud-azure-arc.md) — Azure Arc enrolment for post-provisioning management

**Pricing sources (verified 2026-06-16):**
- Contabo Cloud VPS 10: [contabo.com/en/upsell-vps-10-20/](https://contabo.com/en/upsell-vps-10-20/)
- Hetzner Cost-Optimized (CX33/CAX21): [hetzner.com/cloud/cost-optimized](https://www.hetzner.com/cloud/cost-optimized)
