---
source: https://gemini.google.com/share/a4b01a2b65b2
model: Gemini 3.5 Flash
date: 2026-06-15
---

# VPS Selection for Homelab Ansible Playground

## Topic

A discussion about selecting a **budget-friendly European VPS provider** for use as an Ansible playground — a safe, disposable environment to develop and test Ansible playbooks before applying them to the physical homelab server, which runs Ubuntu 24.04 LTS.

The target spec is **2–4 vCPU, 8 GB RAM, public IPv4**, with the ability to **deallocate** (destroy and recreate) to minimise costs during intermittent use.

---

## Key Findings

### 1. Budget VPS landscape in Europe

Five major budget providers compete in the EU VPS market:

| Provider | Headquarters | Data Centres | Pricing Model |
|---|---|---|---|
| **Contabo** | Munich, DE | Munich, Nuremberg, Berlin | Fixed monthly subscription |
| **Netcup** | Nuremberg, DE | Nuremberg, Vienna | Monthly / annual subscription |
| **Hetzner** | Nuremberg, DE | Nuremberg, Helsinki | Hourly (Pay-As-You-Go) |
| **Scaleway** | Paris, FR | Paris, Amsterdam, Warsaw | Hourly (Pay-As-You-Go) |
| **OVHcloud** | Roubaix, FR | Warsaw, Paris, Strasbourg | Fixed monthly (VPS line) |

### 2. Price comparison — 2–4 vCPU, 8 GB RAM, public IPv4

| Provider | Plan | Spec | Price/mo (EUR) | Price/mo (PLN) | Hourly billing |
|---|---|---|---|---|---|
| Contabo | VPS Cloud S | 4 vCPU, 8 GB RAM, 500 GB SSD | ~€5.50 | ~24,30 PLN | ❌ |
| Netcup | VPS 1000 G11 | 4 vCPU, 8 GB RAM, 160 GB SSD | ~€6.30 | ~27,80 PLN | ❌ |
| Hetzner | CX32 (Intel) | 2 vCPU, 8 GB RAM, 80 GB NVMe | ~€7.80 | ~34,40 PLN | ✅ (~0,05 PLN/h) |
| Hetzner | CPX31 (AMD) | 4 vCPU, 8 GB RAM, 120 GB NVMe | ~€8.70 | ~38,40 PLN | ✅ (~0,06 PLN/h) |
| OVHcloud | VPS Comfort | 2 vCPU, 8 GB RAM, 160 GB NVMe | ~€11.50 | ~50,80 PLN | ❌ |

> **Note on VAT**: Prices in EUR from DE-based providers (Hetzner, Netcup, Contabo) include German VAT (19%). When registering from Poland, billing switches to Polish VAT (23%), adding ~3.3% to the final price. PLN estimates above already reflect the 23% rate.

### 3. Deallocation (destroy-and-recreate) support

Only **Hetzner** and **Scaleway** offer true hourly billing with infrastructure-as-code destroy/recreate workflows:

| Provider | Destroy & Recreate | Snapshot cost | Notes |
|---|---|---|---|
| Contabo | ❌ Fixed subscription | N/A | Pay full price regardless of uptime |
| Netcup | ❌ Fixed subscription | N/A | Annual commitment for best pricing |
| **Hetzner** | ✅ API + Ansible module | ~€0.0119/GB/mo | Snapshot → destroy → recreate in <1 min |
| Scaleway | ✅ Instance deletion, keep volume | ~€6-8/mo for 80 GB disk | Block Storage retained; compute deleted |
| OVHcloud | ❌ (VPS line) | N/A | No hourly billing in budget VPS range |

### 4. Hetzner snapshot strategy (recommended approach)

For intermittent use (e.g. 20–30 hours/month), the Hetzner workflow minimises cost:

1. **Initial setup**: Provision CPX31 once, configure fully via Ansible, take a Snapshot
2. **Start session**: Ansible/Hetzner API creates a new instance from the Snapshot (`hcloud_server` module with `snapshot_id`)
3. **Work**: Instance runs; billing accrues at ~€0.012/h (~0,06 PLN/h)
4. **Stop session**: Ansible takes a fresh Snapshot (if state changed) and destroys the instance (`state: absent`)
5. **Idle cost**: Only the Snapshot storage (~€0.48/mo for 40 GB image ≈ 2,10 PLN/mo)

**Estimated monthly cost at 30 h/mo usage**: ~€0.84 (≈ 4,00 PLN) — compared to ~€8.70 fixed subscription.

### 5. Provider analysis matrix

| Criteria | Contabo | Netcup | **Hetzner** | Scaleway | OVHcloud |
|---|---|---|---|---|---|
| Raw resources/€ | ✅ Best (500 GB) | ✅ Good (160 GB) | ⚠️ Adequate (120 GB) | ❌ Low | ❌ Low |
| CPU stability | ❌ Overselling | ✅ Stable | ✅ Excellent | ✅ Good | ✅ Good |
| Hourly billing | ❌ | ❌ | ✅ | ✅ | ❌ |
| Ansible integration | ⚠️ Basic API | ⚠️ Basic API | ✅ Excellent (hcloud) | ✅ Good | ✅ Good |
| Anti-DDoS | ❌ | ❌ | Basic | ❌ | ✅ Excellent |
| Deallocation cost savings | ❌ | ❌ | ✅ ~90% saving | ✅ ~70% saving | ❌ |

---

## Decisions Made

| Decision | Choice | Rationale |
|---|---|---|
| **VPS provider** | **Hetzner** | Only budget provider combining hourly billing, excellent Ansible API module (`hcloud_server`), and CPU stability. Enables the destroy-recreate workflow essential for a playground. |
| **Plan** | **CPX31 (AMD)** | 4 vCPU / 8 GB RAM / 120 GB NVMe. AMD EPYC architecture offers better multi-threading value than CX32 (Intel). Matches the target spec. |
| **Cost strategy** | **Snapshot-based destroy/recreate** | Snapshot storage costs ~€0.48/mo; compute is billed only per active hour. At 30 h/mo total cost is ~€0.84 instead of €8.70. |
| **Workflow** | **Ansible-driven** | Use `hcloud_server` Ansible module to create/destroy instances. Snapshot management also via Ansible/Hetzner API. |

---

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| Contabo VPS Cloud S | ❌ Rejected | Fixed subscription — no hourly billing. Overselling causes variable disk I/O. Cannot deallocate to save cost. |
| Netcup VPS 1000 G11 | ❌ Rejected | Fixed subscription, no hourly billing. Despite excellent stability, the lack of deallocation makes it unsuitable for intermittent playground use. |
| Scaleway (Play/Stardust) | ⚠️ Viable but more expensive idle | Block Storage at €6-8/mo for 80 GB is ~12× more expensive than Hetzner's snapshot storage. Would only make sense for constantly-running workloads. |
| OVHcloud VPS Comfort | ❌ Rejected | No hourly billing in the budget VPS line. Most expensive at €11.50/mo fixed. Anti-DDoS is excellent but not needed for a private playground. |
| DigitalOcean / Linode | ❌ Rejected | US-based, priced in USD, higher base costs (~$48/mo for 2 vCPU / 8 GB). Hourly billing exists but same caveat as Hetzner (stopped instances still cost). |

---

## Open Questions

- **Hetzner account verification**: Hetzner requires identity verification (ID/passport) for new accounts. How long does this take?
- **Region selection**: Nuremberg vs Helsinki — latency difference from Poland to both locations.
- **Ansible dev loop**: Should the playground run Ubuntu 24.04 LTS (matching the homelab) or Ubuntu 24.04 + Docker-in-Docker for testing container roles?
- **Snapshot lifecycle**: Automate snapshot rotation (keep last N snapshots, delete older ones) in the Ansible teardown playbook.

---

## Source

https://gemini.google.com/share/a4b01a2b65b2
