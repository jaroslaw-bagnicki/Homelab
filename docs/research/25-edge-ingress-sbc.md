# 25 — Edge Ingress SBC — Hardware Research for the PL Market

**Source**: OpenCode thread, Aug 09 2026 · Issue [#65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)

**Scope**: Hardware selection for a dedicated edge box on the home LAN running `cloudflared` + Caddy — with prices that are actually reachable in Poland.

**Status**: 📝 Analysis — working selection: **Dell Wyse 3040 thin client, bare-metal `cloudflared` + Caddy (systemd) on Debian minimal** (Alpine Linux trialed in parallel). Decision recorded in [ADR 24](../decisions/24-edge-ingress-appliance.md); RPi 4B documented as the price-sane ARM fallback.

---

## Context

The homelab's public ingress (`cloudflared` + Caddy) currently lives on the M910q (ADR 07/08, V1 design). Moving it to a dedicated, low-power edge box decouples inbound routing from the M910q's lifecycle:

- **ADR 22** is migrating workloads to k3s on the M910q — cluster churn must not drop the public tunnel.
- **ADR 23** scopes the ML110 OMV NAS as storage-only; its web UI still needs a tunnel path (runbook 22 §4d "Phase 2").
- **ADR 20** establishes Caddy as the single routing layer — a stable dedicated device keeps "one Caddyfile is the source of truth".
- **ADR 08** still holds: home ISP is CGNAT; the edge box needs only a single outbound QUIC connection to Cloudflare's edge (UDP 7844). No inbound ports, no router config.

### Architecture split (confirmed)

- **Edge box**: `cloudflared` → Caddy for `*.example.com` (external ingress). The ADR 19 pattern (CF SSL **Full (Strict)** + Cloudflare Origin CA) applies unchanged.
- **M910q**: keeps the internal `.home` Caddy + k3s (ADR 07/06). The tunnel origin moves off the M910q.

---

## PL Market Reality: SBC International MSRP ≠ Reachable Price

Initial research suggested a cheap SBC (e.g. Radxa ZERO 3E at ~$25) as the obvious pick. That price is not reachable in Poland:

- **Botland** (major PL electronics retailer) does not stock Orange Pi or Radxa boards.
- **TME** (Polish distributor) has no Orange Pi boards in its catalog.
- Non-Raspberry Pi SBCs therefore reach Poland only via **Allegro import sellers**, with shipping + markup pushing realistic prices well above international MSRP.

Consequences:
- **Radxa ZERO 3E — dropped** as the headline pick. Its ~$25 MSRP is not a Poland-reachable price; listings are scarce and overpriced when present.
- The cheap-SBC floor doesn't hold: the cheapest reachable GbE SBC (Orange Pi Zero 3 4 GB) runs **~370 PLN** on Allegro (verified Aug 2026) — ~5× the 3040's ~70 PLN.
- At that price point, a **used x86 thin client** becomes cost-competitive — with the side benefit that it reuses the homelab's existing apt/.deb + Ansible toolchain.

> Exact listing prices must be verified on Allegro at purchase time (automated queries are bot-blocked; ranges below are market-level estimates as of Aug 2026).

---

## Candidate Paths

### Path A — Used fanless x86 thin client (selected)

Business thin clients are common and cheap on the Polish used market.

#### Selected unit: Dell Wyse 3040 (~70 PLN used)

| Property | Value |
|---|---|
| CPU | Atom x5-Z8350 (Cherry Trail, 4C) |
| RAM | 2 GB DDR3L (soldered — no upgrade) |
| Storage | 8 GB eMMC (soldered) |
| Network | 1× GbE |
| Power | ~2–3 W idle (fanless) |
| Price | ~70 PLN used |
| OS | Debian minimal (baseline); Alpine Linux trialed |

**Selection rationale:**
- **Insanely cheap in the PL market** — ~70 PLN vs ~370 PLN for the OPi Zero 3 4 GB vs ~280–400 PLN for a used RPi 4B. The 3040 is ~4–5× cheaper than any reachable GbE SBC/RPi.
- **Constrained-resources experiment** — a deliberate 2 GB/8 GB appliance forces minimal, clean engineering; a first-class hobby rationale for this homelab.
- **Bare-metal fits** — `cloudflared` + Caddy as systemd services need ~600–800 MB RAM / ~4 GB disk, leaving room on 2 GB/8 GB (see Deployment Model).

**Accepted constraints:**
- 2 GB RAM / 8 GB eMMC soldered — **zero headroom**. If the edge box ever needs an observability/Arc agent, the fallback (5070) is required.
- Cherry Trail is aging; eMMC write endurance on a 24/7 box is a modest concern (write-light workload mitigates).
- Minimal install must be tuned for 8 GB eMMC — aggressive log rotation, no Docker images.

#### Fallback: Dell Wyse 5070 / HP t640 (~150–250 PLN)

Celeron J4105, 4–8 GB SODIMM (upgradeable), SATA SSD slot, GbE, ~5–8 W idle. The same thin-client class with real headroom — adopted if the 3040's constraints bite.

### Path B — Orange Pi Zero 3 (4 GB) — rejected on price

Real PL price (Allegro, verified Aug 2026) is **~370 PLN for 4 GB** — not the ~130–200 PLN of international pricing, and now pricier than a used RPi 4B.

| Property | Value |
|---|---|
| SoC | Allwinner H618, quad Cortex-A53 |
| RAM | 1/2/4 GB LPDDR4X |
| Storage | microSD only |
| Network | 1× GbE |
| Power | ~2–4 W idle |
| Price | ~370 PLN (Allegro, verified Aug 2026) |
| OS | Armbian / Debian (ARM64) |

**Assessment:**
- Lowest **power** of the two paths, and runs `cloudflared` + Caddy trivially (both Go/ARM64-native, write-light).
- But **no longer lowest cost** — at ~370 PLN it is ~5× the Wyse 3040 and ~30% pricier than a used RPi 4B. Rejected on price.

**Costs:**
- **New provisioning path** — Armbian/ARM64 images, a new Ansible host type and roles; none of the existing x86/Ubuntu tooling applies unchanged.
- **microSD boot** — the classic always-on failure point; acceptable only with a reputable A2 card + `overlayroot` read-only rootfs (write-light workload mitigates wear).

### Path C — Raspberry Pi 4B (used) — ecosystem-safe third option

~280–400 PLN used on Allegro (2 GB from ~280 PLN, 8 GB ~400 PLN). Native GbE, best ecosystem/support. Same ARM64 provisioning cost as Path B (SD/USB boot). At these prices it is the price-sane ARM fallback (cheaper than the OPi Zero 3), but still ~4× the Wyse 3040.

---

## Deployment Model — Bare-Metal vs Docker

The edge box runs exactly two daemons (`cloudflared`, Caddy). **Bare-metal (systemd on minimal Debian) is the recommended model**:

- **Fits the 3040's 2 GB / 8 GB** — Docker would add containerd + images + overlayfs and push RAM past comfort.
- **Fewer layers on a public-facing device** — one less runtime to patch; smaller attack surface.
- **Write-light on eMMC** — no image/container filesystem churn.
- **Config-as-code intact** — the Caddyfile and cloudflared config stay templated by Ansible (ADR 10); both apps ship official apt repos (`pkg.cloudflare.com`, `caddyserver.com`), so updates remain `apt upgrade`.
- **Fleet OS is Ubuntu (ADR 05); the edge appliance uses Debian minimal** — a leaner base for a two-daemon box that keeps the same apt/.deb toolchain and the ADR 06/07 routing semantics.

**Cost:** a new Ansible provisioning path (`edge_host`-style systemd role) diverging from `docker_services` (ADR 10) — an intentional exception for an appliance-class device. Docker remains the documented alternative if fleet consistency ever outweighs minimalism; in that case the Wyse 5070 replaces the 3040.

### OS Evaluation — Debian minimal (baseline) vs Alpine (trial)

| | Debian minimal | Alpine Linux |
|---|---|---|
| Idle RAM | ~250–300 MB | ~60–100 MB |
| Installed disk | ~1.5–2 GB | ~300 MB |
| Package mgr / toolchain | apt/.deb — fits Ansible roles (ADR 10) | apk/musl — roles don't fit |
| cloudflared + Caddy | .deb repos | static Go / musl builds |
| Lifecycle | LTS 5 y | rolling, ~2 y/release |

Both run the same systemd units and identical Caddy/cloudflared configs — only the package layer and provisioning differ. The trial is **sequential on the 3040**: install Debian minimal, validate `cloudflared` + Caddy, reflash Alpine, validate. Debian minimal is the baseline (keeps the apt/Ansible toolchain); Alpine is trialed as the maximally-lean constrained-resources option. The final OS is locked before the `edge_host` role is written.

---

## Comparison

| Dimension | A — Wyse 3040 (bare-metal) | B — Orange Pi Zero 3 | C — RPi 4B (used) | D — Wyse 5070 (Docker fallback) |
|---|---|---|---|---|
| Est. price (PL) | **~70 PLN** | ~370 PLN | ~280–400 PLN | ~150–250 PLN |
| Cost vs ARM options | **~4–5× cheaper** | ~5× the 3040 | ~4× the 3040 (2 GB) | ~2–3× the 3040 |
| Idle power | ~2–3 W | ~2–4 W | ~3–5 W | ~5–8 W |
| RAM | 2 GB soldered (no headroom) | 4 GB | 2–8 GB | 4–8 GB upgradeable |
| Boot storage | 8 GB eMMC | microSD + overlayroot | SD/USB | SATA SSD |
| Deployment model | Bare-metal (systemd) | Bare-metal or Docker | Bare-metal or Docker | Docker (ADR 10 stack) |
| OS/provisioning | Debian minimal, new edge role | Armbian/ARM64, new | RPi OS/ARM64, new | Ubuntu, existing roles |
| Cloudflared + Caddy load | Trivial | Trivial | Trivial | Trivial |
| Spares/repairability (PL) | Good (business gear) | Poor | Good | Good |

**Verdict:** the Wyse 3040 at ~70 PLN is the working selection — cheapest by a wide margin in the PL market (OPi Zero 3 is ~370 PLN, RPi 4B from ~280 PLN) and a deliberate constrained-resources experiment. Bare-metal keeps it viable within 2 GB/8 GB. The Wyse 5070 (Docker-capable, real headroom) is the fallback if the 3040's constraints bite; the RPi 4B (2 GB) is the price-sane ARM fallback if the x86 path is ever abandoned.

---

## Traps Recorded (avoid on any SBC shopping)

- **NanoPi R5C** — its M.2 slot is **E-Key (WiFi/BT only)**, not NVMe; ships with 32 GB eMMC.
- **Orange Pi 3B** — M.2 2280 is **SATA, not NVMe**.
- **Radxa ZERO 3W** — has eMMC but **no ethernet** (WiFi only); only the 3E has GbE, and it boots microSD-only.
- **SBC MSRP vs PL price** — always price-check the Allegro listing, not the vendor's international MSRP. Verified Aug 2026: Orange Pi Zero 3 4 GB ~370 PLN, used RPi 4B from ~280 PLN (2 GB) / ~400 PLN (8 GB).

---

## Open Questions (implementation)

1. **Observability headroom** — does the edge box need an Arc/AMA or OpenTelemetry agent? If yes, the 2 GB 3040 is out and the Wyse 5070 becomes required.
2. **OS trial outcome** — Debian minimal vs Alpine Linux (sequential on-device trial); the final OS is locked before the provisioning role is written.
3. Config-as-code for the edge box — Ansible `edge_host`-style role vs standalone recipe (see [ADR 24](../decisions/24-edge-ingress-appliance.md)).
4. Replace the M910q `homelab-tunnel` + Caddy entirely, or keep both in parallel during migration?
5. Edge box placement on the TL-SG108E (runbook 23) and repointing internal `.home` DNS (ADR 06).
6. Does this ride along with the OMV "Phase 2" tunnel work (runbook 22 §4d)?
7. What happens to the M910q's V1 tunnel → standardize on the ADR 19/20 pattern as part of this move?

---

## References

- [Idea 04 — Dedicated edge device for tunnel + caddy](../ideas/04-edge-device-tunnel-caddy.md)
- [Issue #65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)
- [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md)
- [ADR 07](../decisions/07-reverse-proxy-caddy.md) — Caddy reverse proxy
- [ADR 08](../decisions/08-remote-access-cloudflare-tunnel.md) — Cloudflare Tunnel / CGNAT
- [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md) — HTTPS-only origin (Full (Strict) + Origin CA)
- [ADR 20](../decisions/20-caddy-single-routing-layer.md) — Caddy single routing layer
- [ADR 22](../decisions/22-k3s-arc-homelab.md) — k3s + Azure Arc
- [ADR 23](../decisions/23-nas-on-ml110.md) — ML110 OMV storage-only
- [Research 24 — network topology design](24-network-topology-design.md)
- [Runbook 22 — ML110 OMV setup](../runbooks/22-ml110-omv-setup.md) — §4d "Phase 2" tunnel note
- [Runbook 23 — TL-SG108E switch](../runbooks/23-tl-sg108e-switch.md)
