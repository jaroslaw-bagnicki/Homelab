# Edge Ingress on a Dedicated Thin-Client Appliance

**Date:** 2026-08-09
**Status:** Accepted

---

## Context

The homelab's public ingress (`cloudflared` tunnel + Caddy reverse proxy) currently runs in Docker on the M910q (ADR 07/08, V1 design). Three pressures drive moving it:

- **ADR 22** migrates workloads to k3s on the M910q — cluster churn (upgrades, restarts, node maintenance) must not be able to drop the public tunnel.
- **ADR 23** scopes the ML110 OMV NAS as storage-only; its web UI (`omv.example.com`, runbook 23 §4d "Phase 2") still needs a tunnel path.
- **ADR 20** establishes Caddy as the single routing layer; a stable dedicated device strengthens "one Caddyfile is the source of truth".

The home ISP is CGNAT (ADR 08): the ingress needs only a single outbound QUIC connection to Cloudflare's edge (UDP 7844) — no inbound ports, no router config. Hardware research ([research 25](../research/25-edge-ingress-sbc.md)) showed SBC international MSRP is not reachable in Poland; a used fanless x86 thin client is both cheaper than any reachable SBC/RPi and reuses the fleet's apt/.deb toolchain.

## Decision

Run the homelab's public ingress on a **dedicated, low-power edge appliance** on the home LAN, in front of all backends:

- **Hardware — Dell Wyse 3040** (Atom x5-Z8350, 2 GB DDR3L, 8 GB eMMC, GbE, ~90 PLN used — actual purchase 89,00 PLN on 2026-08-13, ~2–3 W fanless). Selected as a deliberate constrained-resources experiment and by far the cheapest reachable GbE device in PL. The Wyse 5070 (4 GB, SATA SSD) is the accepted fallback if the 2 GB ceiling is hit.
- **Deployment model — bare-metal, not Docker.** `cloudflared` and Caddy install directly on a minimal distro as systemd services. **OS: Debian minimal as the baseline; Alpine Linux trialed in parallel** (sequential on-device trial) as part of the constrained-resources experiment — the Caddy/cloudflared configs are identical either way. Config-as-code preserved: the Caddyfile and cloudflared config are templated by Ansible (ADR 10); Debian keeps the apt/.deb update path.
- **Architecture split.** The edge appliance owns external routing: `*.example.com` → Caddy → backends over the LAN. The M910q keeps the internal `.home` Caddy + k3s (ADR 06/07/22). The tunnel origin moves off the M910q.
- **ADR 19 pattern applies to the homelab edge.** cloudflared → Caddy over HTTPS with Cloudflare Origin CA; CF SSL mode Full (Strict).
- **Provisioning.** A new Ansible `edge_host`-style role (systemd units), distinct from `docker_services`.

## Consequences

- Ingress decoupled from M910q compute — k3s churn never drops external access.
- OMV web UI gains a tunnel path without breaking the storage-only scope (ADR 23).
- Single source of truth for routing stays (ADR 20), now on a stable box.
- **New single point of failure** — the edge appliance is the ingress; if it dies, external access drops until replaced. Cheap to keep a spare; accepted.
- **Bare-metal diverges from the container-first stack** (ADR 03/22) — an intentional exception for a two-daemon, internet-facing appliance: fewer layers, smaller attack surface, less eMMC write wear, fits 2 GB/8 GB.
- **Constrained hardware** — 2 GB RAM / 8 GB eMMC are soldered (no upgrade); zero headroom for full-size agents or Arc enrolment. Monitoring on the appliance must use **lightweight components** — a **Netdata child node** ([ADR 27](27-monitoring-strategy.md)) and **Fluent Bit if adopted as a Tier B component** — and must **not cache/buffer data to the eMMC drive**: only a small RAM buffer is allowed (Netdata `memory mode = ram`, no `dbengine` disk store; Fluent Bit in-memory buffering only). If headroom is exhausted, move to the Wyse 5070. Cherry Trail is aging.
- **Appliance-only OS deviation from ADR 05** — the edge box runs Debian minimal (leaner base, same apt/.deb toolchain) while Ubuntu stays the fleet standard for workload hosts. The Debian-vs-Alpine outcome is locked before the `edge_host` provisioning role is written.
- `.home` DNS (dnsmasq, ADR 06) stays pointed at the M910q for now; repoint only if internal routing ever moves to the edge.

### Alternatives Considered

- **Keep ingress on the M910q (no change)** — loses the decoupling benefit; ingress tied to cluster lifecycle. Rejected.
- **Docker/containers on the edge box** — keeps fleet consistency (ADR 10) but doesn't fit 2 GB/8 GB and adds a runtime layer to a public-facing device. Rejected for the edge; documented as the fallback path in research 25.
- **Orange Pi Zero 3 (ARM)** — ~370 PLN on Allegro (verified Aug 2026): ~4× the 3040, pricier than a used RPi 4B, and needs a new ARM64/Armbian provisioning path. Rejected on price; documented as Path B.
- **Raspberry Pi 4B** — best ecosystem/support but ~280–400 PLN in PL (2–8 GB) — ~3× the 3040. Rejected on cost.
- **Reuse the ML110 or existing M910q** — contradicts ADR 23's storage-only scope / loses the decoupling benefit. Rejected.

---

## References

- [Research 25 — Edge ingress SBC, PL market](../research/25-edge-ingress-sbc.md)
- [Idea 04 — Dedicated edge device for tunnel + caddy](../ideas/04-edge-device-tunnel-caddy.md)
- [Issue #65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) — Dedicated edge device for Cloudflare Tunnel + Caddy ingress
- [ADR 05](../decisions/05-os-decision-ubuntu-server.md) — OS decision (Ubuntu Server)
- [ADR 06](../decisions/06-local-dns-dnsmasq.md) — local DNS
- [ADR 07](../decisions/07-reverse-proxy-caddy.md) — Caddy reverse proxy
- [ADR 08](../decisions/08-remote-access-cloudflare-tunnel.md) — Cloudflare Tunnel / CGNAT
- [ADR 10](../decisions/10-ansible-host-config.md) — Ansible host configuration
- [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md) — HTTPS-only origin (Full (Strict) + Origin CA)
- [ADR 20](../decisions/20-caddy-single-routing-layer.md) — Caddy single routing layer
- [ADR 22](../decisions/22-k3s-arc-homelab.md) — k3s + Azure Arc
- [ADR 23](../decisions/23-nas-on-ml110.md) — ML110 OMV storage-only
