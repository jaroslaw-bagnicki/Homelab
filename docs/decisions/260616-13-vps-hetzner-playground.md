# Use Hetzner CPX31 VPS as Ansible Playground for Homelab

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
- **Deallocatable** — destroy and recreate via API to minimise cost during
  intermittent development sessions (estimated 20–30 h/month usage)
- **Ansible-friendly** — first-class Ansible modules or a clean REST API
  for provisioning and teardown
- **EU-hosted** — low latency from Poland, GDPR-aligned

## Decision

**Use Hetzner Cloud CPX31 (AMD, 4 vCPU, 8 GB RAM) as the Ansible playground
VPS, managed via a snapshot-based destroy/recreate workflow.**

### Workflow

1. **Provision**: `hcloud_server` Ansible module creates a CPX31 instance from
   a pre-configured Snapshot
2. **Develop**: Run Ansible playbooks against the live instance; iterate
3. **Teardown**: Ansible takes a fresh Snapshot (if state changed), then
   destroys the instance (`state: absent`)
4. **Idle**: Only the Snapshot storage is billed (~€0.48/mo for 40 GB image)

### Costs

| Scenario | Monthly cost (EUR) | Monthly cost (PLN) |
|---|---|---|
| Always-on (fixed subscription) | ~€8.70 | ~38,40 PLN |
| Snapshot strategy, 30 h/month | ~€0.84 | ~4,00 PLN |
| Snapshot storage only (idle) | ~€0.48 | ~2,10 PLN |

## Consequences

**Positive:**

- **~90% cost reduction** compared to a fixed-subscription VPS at equivalent
  spec, because compute is only billed during active development sessions
- **Ansible-native provisioning** — the `hcloud_server` module integrates
  directly into the playbook workflow, no wrapper scripts needed
- **Same architecture as production** — AMD EPYC (CPX31) vs Intel (CX32)
  minimises divergence between playground and homelab
- **Low switching cost** — if the provider relation sours, the workflow is
  portable: snapshot → attach volume → recreate on another provider

**Negative:**

- **Requires snapshot lifecycle management** — old snapshots must be pruned
  to avoid storage cost creep
- **No persistent state between sessions** — databases, caches, and scratch
  data are lost on destroy (by design, but means each session starts clean)
- **Vendor lock-in at the snapshot format level** — Hetzner snapshots are not
  portable to other providers; the base Snapshot must be rebuilt if switching

### Alternatives Considered

**Contabo VPS Cloud S** (~€5.50/mo, 4 vCPU, 8 GB, 500 GB SSD). Rejected because
fixed subscription pricing means full cost is paid regardless of uptime.
Known overselling causes variable disk I/O, which could mask or create
performance issues during playbook testing.

**Netcup VPS 1000 G11** (~€6.30/mo, 4 vCPU, 8 GB, 160 GB SSD). Rejected for
the same reason as Contabo — fixed subscription with no hourly billing, despite
excellent stability and competitive pricing.

**Scaleway (Play/Stardust)** — hourly billing is available, but Block Storage
costs (~€6–8/mo for 80 GB disk) are ~12× higher than Hetzner's snapshot
storage. Economical only for constantly-running workloads.

**OVHcloud VPS Comfort** (~€11.50/mo, 2 vCPU, 8 GB, 160 GB NVMe). Rejected as
the most expensive option with no hourly billing in the budget VPS line.
Anti-DDoS is excellent but unnecessary for a private playground.

**Tailscale Funnel / local VM** — running the playground on the homelab itself
(via LXD/KVM or Tailscale Funnel) defeats the purpose: the playground is meant
to be a separate, disposable machine that can be nuked without affecting the
production host.

---

**References:**
- [Research 15: VPS Selection](../research/15-vps-selection.md) — detailed provider comparison, pricing tables, and workflow analysis
- [Research 13: Ansible Adoption](../research/13-ansible-adoption.md) — Ansible strategy for the homelab
- [ADR 4: Hybrid Cloud Strategy](260524-04-hybrid-cloud-azure-arc.md) — Azure Arc enrolment for post-provisioning management
