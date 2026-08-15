# Edge Appliance (Wyse 3040) — Runbook

> Deploy the homelab's **dedicated edge appliance** — bare-metal `cloudflared` + Caddy
> on a Dell Wyse 3040 thin client — as the single public ingress for the LAN.
> Device acquired **2026-08-13**; implementation in progress.
> See [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md),
> [research 25 — PL-market hardware](../research/25-edge-ingress-sbc.md),
> [idea 04](../ideas/04-edge-device-tunnel-caddy.md). Tracked in
> [issue #65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65).

## Goals

- Run `cloudflared` (single outbound QUIC connection to Cloudflare's edge, UDP 7844)
  + Caddy as **systemd services** on a minimal distro — bare-metal, no Docker.
- Own external routing: `*.example.com` → Caddy → backends over the LAN
  (M910q k3s, ML110 OMV, future gear).
- Stay lean: 2 GB RAM / 8 GB eMMC, ~2–3 W idle, fanless.

## Hardware (purchased)

| Item | Detail |
|---|---|
| Dell Wyse 3040 | Atom x5-Z8350 · 2 GB DDR3L · 8 GB eMMC · 1× GbE · fanless |
| Purchase date | 2026-08-13 |
| Device price | 89,00 PLN (~20,70 EUR) — won at auction; the 69,00 PLN offer was closed |
| Charger | 35,94 PLN (~8,36 EUR) — 24,99 PLN + 10,95 PLN shipping |
| **Total** | **124,94 PLN (~29,06 EUR)** |
| Exchange rate | ≈4,30 PLN/EUR (Aug 2026) |

> ⚠ **Charger compatibility**: the device shipped without a charger — verify the
> purchased one matches the Wyse 3040's power spec (barrel connector size + voltage)
> before first boot.

## Prerequisites

- Wyse 3040 + verified charger (see Hardware above)
- USB flash drive + flasher (balenaEtcher / `dd`)
- OS images for the trial: **Debian minimal** (netinst) + **Alpine Linux**
- Console or SSH reachability during setup
- Refs: [research 25](../research/25-edge-ingress-sbc.md) (hardware), [ADR 24](../decisions/24-edge-ingress-appliance.md) (decision), [runbook 23](23-tl-sg108e-switch.md) (switch placement)

---

## 1. OS Trial — Debian minimal vs Alpine (sequential)

> *To be completed.* Install Debian minimal → validate `cloudflared` + Caddy → reflash
> Alpine → validate. Lock the OS before the provisioning role is written (research 25 §OS Evaluation).

## 2. Base Setup

> *To be completed.* Static IP on the reserved `192.168.2.x` block (research 24), SSH,
> hardening — mirror [runbook 1](1-init.md).

## 3. cloudflared — Tunnel

> *To be completed.* Install via the official apt repo (`pkg.cloudflare.com`), configure
> the tunnel token, systemd unit, outbound-only.

## 4. Caddy — Reverse Proxy

> *To be completed.* Install via the Caddy apt repo, Caddyfile templated by Ansible
> (ADR 10), Cloudflare Origin CA certs, CF SSL mode Full (Strict) — the ADR 19 pattern.

## 5. Validation

> *To be completed.* End-to-end checks: `*.example.com` → Cloudflare edge → edge box →
> backend; failover behaviour with the M910q tunnel (replace vs parallel, idea 04).

## 6. Switch Placement

> *To be completed.* Port on the TL-SG108E (runbook 23), static IP per research 24's
> reserved block.
