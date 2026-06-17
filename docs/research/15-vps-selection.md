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
| Contabo | Cloud VPS 10 | 4 vCPU, 8 GB RAM, 75 GB NVMe or 150 GB SSD | **€5.50** | ~25,00 PLN | ❌ |
| Netcup | VPS 1000 G11 | 4 vCPU, 8 GB RAM, 160 GB SSD | ~€6.30 | ~28,50 PLN | ❌ |
| Hetzner | **CX33** (Cost-Optimized) | 4 vCPU, 8 GB RAM, 80 GB SSD | **€8.99** | ~40,80 PLN | ✅ (€0.0144/h) |
| Hetzner | CAX21 (Cost-Optimized, Ampere) | 4 vCPU, 8 GB RAM, 80 GB SSD | **€10.99** | ~49,90 PLN | ✅ (€0.0176/h) |
| OVHcloud | VPS Comfort | 2 vCPU, 8 GB RAM, 160 GB NVMe | ~€11.50 | ~52,20 PLN | ❌ |

> **Note on VAT**: Prices in EUR from DE-based providers (Hetzner, Netcup, Contabo) include German VAT (19%). When registering from Poland, billing switches to Polish VAT (23%), adding ~3.3% to the final price. PLN estimates above are approximate. Hetzner prices shown excl. VAT (0% displayed on site); add ~23% for Polish billing.

### 3. Deallocation (destroy-and-recreate) support

Only **Hetzner** and **Scaleway** offer true hourly billing with infrastructure-as-code destroy/recreate workflows. **Contabo** has a fixed subscription but supports destroy/recreate via the `cntb` CLI — you still pay full price, but can re-image to a clean state programmatically.

| Provider | Destroy & Recreate | Snapshot cost | Notes |
|---|---|---|---|
| Contabo | ✅ CLI (`cntb create/stop instance`) + Cloud-Init | N/A (included snapshot) | Pay full price regardless of uptime, but CLI enables automated provisioning and re-imaging. `cntb` is a Go-based OSS CLI (v1.6, GPL-3.0). |
| Netcup | ❌ Fixed subscription | N/A | Annual commitment for best pricing |
| **Hetzner** | ✅ API + Ansible module | ~€0.0119/GB/mo | CX33: Snapshot → destroy → recreate in <1 min |
| Scaleway | ✅ Instance deletion, keep volume | ~€6-8/mo for 80 GB disk | Block Storage retained; compute deleted |
| OVHcloud | ❌ (VPS line) | N/A | No hourly billing in budget VPS range |

### 4. Snapshot destroy/recreate strategy (Hetzner only)

For intermittent use (e.g. 20–30 hours/month), Hetzner's hourly billing + snapshot workflow minimises cost:

1. **Initial setup**: Provision CX33 once, configure fully via Ansible, take a Snapshot
2. **Start session**: Ansible/Hetzner API creates a new instance from the Snapshot (`hcloud_server` module with `snapshot_id`)
3. **Work**: Instance runs; billing accrues at ~€0.0144/h
4. **Stop session**: Ansible takes a fresh Snapshot (if state changed) and destroys the instance (`state: absent`)
5. **Idle cost**: Only the Snapshot storage (~€0.48/mo for 40 GB image)

**Estimated monthly cost at 30 h/mo usage with CX33**: ~€0.91 (snapshot storage €0.48 + compute €0.43) — compared to €8.99 fixed max.

**Contabo has no hourly billing**, so the full €5.50/mo is charged regardless of uptime. However, at €5.50/mo it's already cheaper than Hetzner CX33's fixed max (€8.99). The break-even point for Hetzner's snapshot strategy vs Contabo fixed is ~350 h/mo — well above realistic playground usage, making **Contabo the cheaper option** for always-on or moderately-used playgrounds.

### 5. Provider analysis matrix

| Criteria | Contabo | Netcup | **Hetzner (CX33)** | Scaleway | OVHcloud |
|---|---|---|---|---|---|
| Raw resources/€ | ✅ Good (75 GB NVMe / 150 GB SSD) | ✅ Good (160 GB) | ⚠️ Adequate (80 GB) | ❌ Low | ❌ Low |
| CPU stability | ❌ Overselling | ✅ Stable | ✅ Excellent | ✅ Good | ✅ Good |
| Hourly billing | ❌ | ❌ | ✅ | ✅ | ❌ |
| Automation (CLI/API) | ✅ **cntb CLI** (v1.6, Go, OAuth2 + Cloud-Init) | ⚠️ Basic API | ✅ Excellent (hcloud) | ✅ Good | ✅ Good |
| Anti-DDoS | ❌ | ❌ | Basic | ❌ | ✅ Excellent |
| Fixed monthly cost | **€5.50** | €6.30 | **€8.99** | N/A (hourly) | €11.50 |

---

## Decisions Made

> ⚠️ **Pricing correction**: The Gemini conversation quoted CPX31 at ~€8.70/mo, but actual Hetzner CPX31 is €62.99/mo. The correct equivalent at that price point is **CX33** (Cost-Optimized, older shared hardware) at €8.99/mo.

| Decision | Choice | Rationale |
|---|---|---|
| **VPS provider** | **Contabo Cloud VPS 10** (€5.50/mo fixed) | At €5.50/mo for 4 vCPU / 8 GB / 75 GB NVMe it's the cheapest option. The `cntb` CLI provides automation parity with Hetzner for provisioning. |
| **Cost strategy** | Fixed monthly subscription | €5.50/mo flat — no hourly tracking, no snapshot lifecycle management needed. The break-even point where Hetzner's hourly billing would be cheaper (~350 h/mo) is well above realistic playground usage. |
| **Workflow** | Ansible-driven, with `cntb` CLI for provisioning | Contabo lacks a native Ansible collection, but `cntb` CLI (Go, OAuth2, Cloud-Init support) automates create/stop/start operations. Ansible's `command` module wraps `cntb`. |

---

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| **Contabo Cloud VPS 10** (€5.50/mo) | ✅ **Preferred (lowest fixed cost)** | At €5.50/mo for 4 vCPU / 8 GB / 75 GB NVMe, it's the cheapest always-on option. The lack of hourly billing is offset by the low flat rate — even with Hetzner's snapshot strategy, you'd need very low usage (<60 h/mo) to beat €5.50. |
| **Hetzner CX33** (€8.99/mo, €0.0144/h) | ⚠️ Viable (better for very intermittent use) | Hourly billing + snapshot strategy wins only if usage is <60 h/mo (break-even vs Contabo €5.50). Better Ansible integration (`hcloud_server` module), guaranteed CPU stability, no overselling. |
| Netcup VPS 1000 G11 | ❌ Rejected | Fixed subscription at €6.30/mo — more expensive than Contabo with less value. No hourly billing. |
| Scaleway (Play/Stardust) | ❌ Rejected | Block Storage at €6-8/mo for 80 GB disk makes idle cost higher than Contabo's full subscription. |
| OVHcloud VPS Comfort | ❌ Rejected | Most expensive at €11.50/mo fixed. Anti-DDoS is excellent but unnecessary for a private playground. |
| DigitalOcean / Linode | ❌ Rejected | US-based, higher base costs (~$48/mo for 2 vCPU / 8 GB). |

---

## Open Questions

- **Contabo overselling impact**: How noticeable is the variable disk I/O for Ansible dev workflows (mostly SSH + package installs)?
- **`cntb` in Ansible dev loop**: Use `cntb create instance` with Cloud-UserData for first-boot setup, then Ansible for post-provisioning config. Does Cloud-Init handle SSH key injection reliably on Contabo?
- **Snapshots via `cntb`**: Does `cntb` support taking/restoring snapshots for clean re-imaging, or is that panel-only?
- **Region selection**: Contabo offers Munich, Nuremberg, Berlin — any latency difference from Poland?
- **Ansible dev loop**: Should the playground run Ubuntu 24.04 LTS (matching the homelab) or Ubuntu 24.04 + Docker-in-Docker for testing container roles?

---

## Verified Pricing Sources

Prices verified on 2026-06-16 directly from provider websites:

| Provider | Plan | Source |
|---|---|---|
| **Contabo** | Cloud VPS 10 | [contabo.com/en/upsell-vps-10-20/](https://contabo.com/en/upsell-vps-10-20/) |
| **Hetzner** | CX33 / CAX21 (Cost-Optimized) | [hetzner.com/cloud/cost-optimized](https://www.hetzner.com/cloud/cost-optimized) |

> **Note**: The Gemini conversation quoted Hetzner CPX31 at ~€8.70/mo, but the actual CPX31 is €62.99/mo. The ~€9 bracket is the **Cost-Optimized** tier (CX33/CAX21) — older shared hardware, not the regular Cloud line.

## Source

https://gemini.google.com/share/a4b01a2b65b2
