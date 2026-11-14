# Remote Access — Cloudflare Tunnel on the Edge Appliance

**Date:** 2026-11-14
**Status:** Accepted

---

## Context

The homelab sits behind CGNAT — no public inbound — so remote access needs a
tunnel or a VPN (ADR 08). The dedicated edge appliance (ADR 24) already carries
the LAN plane (Technitium DNS + Caddy, ADR 40); the public plane
(`cloudflared` + origin Caddy) still runs in Docker on the cloudlab VPS
(ADR 19), and issue #81 held the move to `edge` until the remote-access
question was decided: Cloudflare Tunnel vs VPN/Tailscale.

That question is now decided: **Cloudflare Tunnel stays the remote-access
mechanism, and it moves to `edge`.** A VPN (WireGuard/Tailscale) was
considered and set aside: it adds a second ingress to operate and audit, while
the tunnel already terminates TLS at the Cloudflare edge, carries Access
policies, and is already the fleet's pattern (ADR 19). If a VPN is wanted
later, it can be added on the router (ADR 48) without changing this
decision.

This ADR also settles the Caddy topology question that came up during the
cloudlab → `lab` Docker migration (runbook 47): **one Caddy on `edge` with
two zones** — the existing `*.internal` sites (TLS leaves from step-ca,
ADR 40) and the new public `*.cloud5.ovh` zone (plain HTTP on loopback,
TLS at the CF edge, ADR 19). No separate public Caddy on `lab`: the Docker
Caddy there is the origin router inside `homelab_net` only, published on the
LAN IP for the edge to proxy to. ADR 20's single-routing-layer rule extends
to the edge Caddy: all public hostname → backend mapping lives in the
templated Caddyfile, the tunnel carries no per-service rules.

## Decision

**Public ingress = Cloudflare Tunnel (`cloudflared`, bare-metal systemd
service) on the `edge` appliance, terminating on the edge Caddy over plain
HTTP on loopback (`127.0.0.1:80`), TLS at the Cloudflare edge (ADR 19
pattern). The edge Caddyfile carries both zones: `*.internal` (step-ca
leaves) and the public domain zone (proxied to the `lab` origin).**

- `cloudflared` installs as a native binary + systemd service via a new
  Ansible `cloudflared` role in `playbook-edge.yml` (after `caddy`), token
  from Key Vault secret `cloudflared-tunnel-token-edge` (ADR 24 deployment
  model: bare-metal, no Docker on the edge box).
- The tunnel is **moved, not duplicated**: the existing tunnel token is
  reused so the `cloud5.ovh` CNAME (`<tunnel-uuid>.cfargotunnel.com`) needs
  no DNS change; its public hostnames point at `http://127.0.0.1:80` on the
  edge connector.
- Edge Caddy gains `caddy_public_sites` (the `cloud5.ovh` apex + wildcard),
  each `http://` site reverse-proxying to the lab origin
  (`http://192.168.2.200:8080`) with `Host` preserved, so the lab Docker
  Caddy keeps host-based routing inside the container network.
- `lab` publishes only its origin Caddy on the LAN (`192.168.2.200:8080`),
  UFW-restricted to the edge's IP; this plaintext edge→lab hop is the one
  new ADR 34 temporary exception (removal condition recorded there).
- `cloudlab` loses its ingress role entirely; the VPS keeps only base
  management (Ansible + Arc) until the decommission decision — decommission
  itself is out of scope here and tracked via ADR 13 / #44.

## Consequences

- Positive: both routing planes consolidate on the low-power edge box
  (ADR 24's original goal); `lab` becomes pure compute again; cloudlab is
  disposable once the workload migration (runbook 47) completes; one
  Caddyfile is the single source of truth for internal + public routing.
- Negative: `edge` becomes the single point of failure for public access
  (accepted in ADR 24 — 2 GB/8 GB box, snapshotted per runbook 27); the
  plaintext edge→lab origin hop needs the ADR 34 exception until the k3s
  ingress (ADR 22) replaces it.
- The remote-access hold on #81 is lifted by this ADR; #65's remaining
  scope is the decommission record.

## Alternatives Considered

- **VPN / Tailscale on the router** — adds a second ingress mechanism to
  operate; rejected for now, can be layered later on the OPNsense router
  (ADR 48) without touching the tunnel.
- **Tunnel on `lab` (status quo ante)** — rejected: cluster churn on the
  workload host must not be able to drop public access (ADR 24 pressure
  #1); `lab` is compute-only.
- **Separate public Caddy on `lab` alongside the edge Caddy** — rejected:
  splits routing across two Caddyfiles (the ADR 20 failure mode); the lab
  Caddy stays origin-only inside the Docker network.

---

## References

- [ADR 08 — Remote Access: Cloudflare Tunnel / CGNAT](08-remote-access-cloudflare-tunnel.md)
- [ADR 19 — Cloudflare Tunnel HTTP origin](19-cloudflare-tunnel-http-origin.md)
- [ADR 24 — Edge ingress appliance](24-edge-ingress-appliance.md)
- [ADR 40 — Internal DNS + Caddy on edge](40-internal-dns-proxy-edge.md)
- [ADR 20 — Caddy single routing layer](20-caddy-single-routing-layer.md)
- [ADR 34 — LAN TLS only](34-lan-tls-only.md) (edge→lab origin exception)
- [ADR 22 — k3s migration](22-k3s-arc-homelab.md) · [runbook 47 — cloudlab → lab Docker migration](../runbooks/47-migrate-cloudlab-docker-to-lab.md)
- [Issue #65 — Dedicated edge appliance](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) · [Issue #81 — move public ingress to edge](https://github.com/jaroslaw-bagnicki/Homelab/issues/81)
