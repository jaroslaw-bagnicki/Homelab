# 25 — Edge Ingress SBC — Hardware Research for the PL Market

**Source**: OpenCode thread, Aug 09 2026 · Issue [#65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)

**Scope**: Hardware selection for a dedicated edge box on the home LAN running `cloudflared` + Caddy — with prices that are actually reachable in Poland.

**Status**: 📝 Analysis — two viable hardware paths compared (used x86 thin client vs Orange Pi Zero 3 ARM); final pick TBD in the decision ADR after Allegro price verification.

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
- The realistic floor for a GbE SBC in PL is ~130–200 PLN, not ~100 PLN.
- At that price point, a **used x86 thin client** becomes cost-competitive — with the side benefit that it reuses the homelab's existing Ubuntu Server + Ansible toolchain.

> Exact listing prices must be verified on Allegro at purchase time (automated queries are bot-blocked; ranges below are market-level estimates as of Aug 2026).

---

## Candidate Paths

### Path A — Used fanless x86 thin client (recommended for toolchain reuse)

Dell Wyse 5070, HP t640, and similar business thin clients are common on the Polish used market.

| Property | Value |
|---|---|
| CPU | Celeron J4105 (Gemini Lake, 4C) or similar |
| RAM | 4–8 GB (SODIMM, upgradeable) |
| Storage | SATA/mSATA SSD (real disk, no microSD) |
| Network | 1× GbE |
| Power | ~5–8 W idle (fanless) |
| Price | ~150–250 PLN used |
| OS | Ubuntu Server — **same as the M910q (ADR 05)** |

**Why it fits this homelab:**
- **Reuses the entire existing provisioning stack** — Ubuntu Server (ADR 05), the `common`/`security`/`docker_host` Ansible roles (ADR 10). No new ARM64/Armbian path to build and maintain.
- **Reliable storage** — SSD boot, no microSD wear/corruption risk on an always-on appliance.
- **Repairability & spares** — business hardware, parts available in PL.
- Consistent with how the homelab already chose the M910q over an RPi for value (ADR 01, research 01).

**Costs:** ~5–8 W idle vs ~2–4 W for an SBC → roughly +10–20 PLN/year electricity at PL residential tariffs — negligible.

### Path B — Orange Pi Zero 3 (4 GB) — cheapest ARM GbE

The cheapest reachable ARM board with real Gigabit Ethernet in PL.

| Property | Value |
|---|---|
| SoC | Allwinner H618, quad Cortex-A53 |
| RAM | 1/2/4 GB LPDDR4X |
| Storage | microSD only |
| Network | 1× GbE |
| Power | ~2–4 W idle |
| Price | ~130–200 PLN (Allegro import) |
| OS | Armbian / Debian (ARM64) |

**Why consider it:**
- **Lowest cost and lowest power** of the two paths.
- Runs `cloudflared` + Caddy trivially (both Go/ARM64-native, write-light).

**Costs:**
- **New provisioning path** — Armbian/ARM64 images, a new Ansible host type and roles; none of the existing x86/Ubuntu tooling applies unchanged.
- **microSD boot** — the classic always-on failure point; acceptable only with a reputable A2 card + `overlayroot` read-only rootfs (write-light workload mitigates wear).

### Path C — Raspberry Pi 4B (used) — ecosystem-safe third option

~200–280 PLN used on Allegro. Native GbE, best ecosystem/support. Same ARM64 provisioning cost as Path B (SD/USB boot), at higher price — noted for completeness, not recommended over Path B at current PL prices.

---

## Comparison

| Dimension | A — Used x86 thin client | B — Orange Pi Zero 3 | C — RPi 4B (used) |
|---|---|---|---|
| Est. price (PL) | ~150–250 PLN | ~130–200 PLN | ~200–280 PLN |
| Idle power | ~5–8 W | ~2–4 W | ~3–5 W |
| Boot storage | SSD (SATA) | microSD + overlayroot | SD/USB |
| OS/provisioning | Ubuntu Server, existing roles (ADR 10) | Armbian/ARM64, new | Raspberry Pi OS/ARM64, new |
| Cloudflared + Caddy load | Trivial | Trivial | Trivial |
| Ecosystem/support | Mature x86 | Community (Armbian) | Best-in-class |
| Spares/repairability (PL) | Good (business gear) | Poor | Good |

**Verdict direction:** for an always-on appliance whose whole job is *not dropping ingress*, Path A (used x86 thin client) gives the most reliability per zloty and zero toolchain divergence. Path B wins only if absolute lowest power/hardware cost is the deciding factor. The final pick is recorded as an open question for the decision ADR.

---

## Traps Recorded (avoid on any SBC shopping)

- **NanoPi R5C** — its M.2 slot is **E-Key (WiFi/BT only)**, not NVMe; ships with 32 GB eMMC.
- **Orange Pi 3B** — M.2 2280 is **SATA, not NVMe**.
- **Radxa ZERO 3W** — has eMMC but **no ethernet** (WiFi only); only the 3E has GbE, and it boots microSD-only.
- **SBC MSRP vs PL price** — always price-check the Allegro listing, not the vendor's international MSRP.

---

## Open Questions (carried to the decision ADR)

1. **Final hardware pick** — after verifying exact Allegro prices for Path A vs Path B.
2. Config-as-code for the edge box — Ansible `docker_services`-style role vs standalone recipe.
3. Replace the M910q `homelab-tunnel` + Caddy entirely, or keep both in parallel during migration?
4. Edge box placement on the TL-SG108E (runbook 23) and repointing internal `.home` DNS (ADR 06).
5. Does this ride along with the OMV "Phase 2" tunnel work (runbook 22 §4d)?
6. What happens to the M910q's V1 tunnel → standardize on the ADR 19/20 pattern as part of this move?

---

## References

- [Idea 04 — Dedicated edge device for tunnel + caddy](../ideas/04-edge-device-tunnel-caddy.md)
- [Issue #65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)
- [ADR 07](../decisions/07-reverse-proxy-caddy.md) — Caddy reverse proxy
- [ADR 08](../decisions/08-remote-access-cloudflare-tunnel.md) — Cloudflare Tunnel / CGNAT
- [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md) — HTTPS-only origin (Full (Strict) + Origin CA)
- [ADR 20](../decisions/20-caddy-single-routing-layer.md) — Caddy single routing layer
- [ADR 22](../decisions/22-k3s-arc-homelab.md) — k3s + Azure Arc
- [ADR 23](../decisions/23-nas-on-ml110.md) — ML110 OMV storage-only
- [Research 24 — network topology design](24-network-topology-design.md)
- [Runbook 22 — ML110 OMV setup](../runbooks/22-ml110-omv-setup.md) — §4d "Phase 2" tunnel note
- [Runbook 23 — TL-SG108E switch](../runbooks/23-tl-sg108e-switch.md)
