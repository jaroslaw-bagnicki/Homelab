# Use Contabo Cloud VPS 10 as Ansible Playground for Homelab

**Date:** 2026-06-16
**Status:** Accepted

---

## Context

The homelab server (Lenovo ThinkCentre M910q Tiny, Ubuntu 24.04 LTS) needs to be
**rebuilt from scratch** — downgrading from Ubuntu 26.x to 24.04 LTS and adopting
**Ansible** for declarative, GitOps-style host configuration management (see
[research 13](../research/13-ansible-adoption.md)). Applying untested Ansible
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

### Cost comparison

| Provider | Plan | Spec | Monthly cost (EUR) | Hourly billing |
|---|---|---|---|---|
| **Contabo** | **Cloud VPS 10** | 4 vCPU, 8 GB, 75 GB NVMe / 150 GB SSD | **€5.50** | ❌ Fixed sub |
| Hetzner | CX33 (Cost-Optimized) | 4 vCPU, 8 GB, 80 GB SSD | **€8.99** max | ✅ €0.0144/h |
| Hetzner | CAX21 (Cost-Optimized, Ampere) | 4 vCPU, 8 GB, 80 GB SSD | **€10.99** max | ✅ €0.0176/h |

Contabo is **€3.49/mo cheaper** than Hetzner CX33 on fixed subscription.
The break-even point where Hetzner's snapshot strategy beats Contabo's fixed
rate is ~350 h/mo — well above realistic playground usage, making Contabo the
cheaper option even when the playground is always on.

### Contabo term discounts

| Term | Monthly price |
|---|---|
| 1 month | €5.50 |
| 6 months | €4.95 (save 10%) |
| 12 months | €4.40 (save 20%) |

No setup fee.

### Workflow

1. **Provision**: `cntb create instance` with Cloud-Init user data provisions
   the VPS with Ubuntu 24.04 LTS; SSH key injection handled via Cloud-Init.
   The `cntb` CLI (Go, OAuth2 auth, v1.6) is installed from GitHub releases.
2. **Configure**: `ansible-playbook -i inventory.ini playbook.yml` configures
   OS, firewall, users, Docker, and Azure Arc agent
3. **Develop**: Run and iterate Ansible playbooks against the live instance
4. **Reset when needed**: Re-image via `cntb create instance` (or panel) to a
   clean base; re-run Ansible
5. **Always-on cost**: €5.50/mo flat — no hourly tracking needed

## Consequences

**Positive:**

- **Lowest fixed monthly cost** — €5.50/mo (€4.40/mo on annual commit) is
  cheaper than any Hetzner equivalent (€8.99/mo CX33 minimum)
- **Generous storage** — 75 GB NVMe or 150 GB SSD; 1 Snapshot included
- **Unlimited traffic** — no transfer cap to worry about during Ansible
  testing with package downloads, Docker pulls, etc.
- **Simple cost model** — fixed subscription, no hourly tracking, no
  snapshot lifecycle management
- **Playground is always available** — no spin-up delay; SSH in and work
  immediately

**Negative:**

- **No hourly billing** — full €5.50/mo charged whether the VPS runs 1 hour
  or 720 hours per month
- **Overselling risk** — Contabo is known for variable disk I/O under load
  due to shared resources; could surface timing-related issues in playbook
  testing that don't reproduce on the homelab
- **200 Mbit/s port** — slower than Hetzner's port speeds; may be noticeable
  during large package installations
- **No native Ansible collection** — Contabo lacks a first-party Ansible
  module; automation relies on the `cntb` CLI wrapped via Ansible's
  `command` module or a custom script

### Alternatives Considered

**Hetzner CX33** (€8.99/mo, €0.0144/h). The closest Hetzner equivalent.
Offers hourly billing with snapshot-based destroy/recreate, excellent
`hcloud_server` Ansible module, and stable CPU performance with no overselling.
Rejected as the primary choice because it costs **63% more** than Contabo on
a fixed subscription (€8.99 vs €5.50). The hourly billing advantage only pays
off below ~60 h/mo usage — but the playground will be online frequently enough
that the simpler cost model of Contabo wins.

**Netcup VPS 1000 G11** (~€6.30/mo, 4 vCPU, 8 GB, 160 GB SSD). More expensive
than Contabo with no compensating advantage. No hourly billing.

**Scaleway (Play/Stardust)** — hourly billing available but Block Storage at
€6–8/mo for the disk alone costs more than Contabo's full subscription.

**OVHcloud VPS Comfort** (~€11.50/mo, 2 vCPU, 8 GB, 160 GB NVMe). Most
expensive option with only 2 vCPU. No hourly billing in the budget VPS line.
Excellent anti-DDoS but unnecessary for a private playground.

**Tailscale Funnel / local VM** — running the playground on the homelab itself
(via LXD/KVM or Tailscale Funnel) defeats the purpose: the playground is meant
to be a separate, disposable machine that can be nuked without affecting the
production host.

---

**References:**
- [Research 15: VPS Selection](../research/15-vps-selection.md) — detailed provider comparison, corrected pricing tables, and analysis
- [Research 13: Ansible Adoption](../research/13-ansible-adoption.md) — Ansible strategy for the homelab
- [ADR 4: Hybrid Cloud Strategy](260524-04-hybrid-cloud-azure-arc.md) — Azure Arc enrolment for post-provisioning management
