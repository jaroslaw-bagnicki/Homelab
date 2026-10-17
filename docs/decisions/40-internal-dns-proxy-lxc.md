# Internal DNS and Reverse Proxy — Technitium + Caddy in One LXC on the pve Node

**Date:** 2026-10-17
**Status:** Accepted

---

## Context

[ADR 37](37-lan-name-space-internal.md) made `.internal` the LAN name space and retired DNSMasq with
`.home` — but nothing was deployed in its place, so the fleet has **no LAN name resolution at all**:
nodes are reached by static IP ([ADR 31](31-static-address-scheme.md)) and mDNS `.local` names only.
[ADR 34](34-lan-tls-only.md) requires TLS on every LAN service, and the private CA that would make
that authenticated exists ([ADR 38](38-private-ca-hierarchy-and-custody.md), `step-ca` in LXC 215) but
issues nothing yet — [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142) and
[#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) are open behind a reverse proxy that
does not exist.

Three constraints shape the answer:

- **Public ingress is on hold** pending a remote-access decision (VPN, possibly Tailscale). The edge
  appliance built for Cloudflare Tunnel + Caddy ([ADR 24](24-edge-ingress-appliance.md)) therefore has
  no active job, and the LAN proxy must not depend on it.
- **The router is not the proxy.** Running Caddy on OPNsense is technically possible but rejected
  ([research 39](../research/39-caddy-on-opnsense-rejected.md)).
- **The resolver choice was open.** [Research 35 §6](../research/35-private-ca-and-lan-naming.md) left
  DNSMasq / Unbound / AdGuard Home / BIND 9 open; [research 38](../research/38-technitium-dns.md)
  compares them against a fleet that needs an authoritative `internal.` zone, a k3s registration path
  and an mDNS bridge, and lands on Technitium DNS.

[Idea 10](../ideas/10-internal-ca-dns-stack.md) already framed the stack as **resolver + proxy + CA**
in one place; this ADR fixes what the two new pieces are and where they run.

## Decision

**Run Technitium DNS and Caddy natively in one unprivileged LXC on the `pve` node, and make that guest
the LAN's name-resolution and routing entry point.**

- **LXC 216, `192.168.2.216`** — an unprivileged guest on `pve`, next free `21x` address, allocated per
  [ADR 31](31-static-address-scheme.md). One guest, not two.
- **Technitium DNS** is authoritative for `internal.` and the fleet's resolver: a wildcard
  `*.internal` → `.216`, static `A` records for nodes and services, recursive/forwarded upstream over
  **DoT**. Zone changes go through its REST API, driven by Ansible; the admin password comes from Key
  Vault.
- **Caddy** is the **single LAN reverse proxy** ([ADR 20](20-caddy-single-routing-layer.md)), with its
  Caddyfile in the repo and rendered by Ansible. It serves `https://<service>.internal` and forwards to
  the service's real address on the LAN.
- **Certificates come from `step-ca` in LXC 215** over ACME, starting with **per-service leaves**
  (HTTP-01). A `*.internal` wildcard via DNS-01 is a later optimisation, not a prerequisite; root
  distribution to clients stays [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144).
- **Native systemd units, not a Docker Compose stack.** Both services need host-level networking —
  mDNS visibility, real client IPs, and UFW as the only firewall (a Docker-published port bypasses it,
  the trap already recorded for the VictoriaLogs workload) — so a container adds a daemon and a boot
  ordering dependency without adding isolation.
- **The guest's own resolver is Technitium on `127.0.0.1`**, so `ca.internal` and every other in-fleet
  name resolves on the box that needs them.
- **mDNS bridging is optional and later.** All nodes are Ansible-managed and statically addressed, so
  static records cover the fleet; Technitium's mDNS app is adopted only if discovery of
  DHCP/mobile devices becomes useful.
- **Out of scope here:** DHCP DNS hand-out (the mesh gateway today, OPNsense later — clients adopt the
  resolver per-device meanwhile), k3s service registration (`*.internal` wildcard to the ingress VIP
  first, ExternalDNS once k3s exists), and remote access (Tailscale split DNS pointing at this resolver
  if that route is chosen).

The edge appliance ([ADR 24](24-edge-ingress-appliance.md)) is **not** the LAN proxy. It stays
provisioned and unmodified; its public-ingress purpose is parked with the VPN decision, and ADR 24's
internal-routing role is not exercised.

## Consequences

- **`.internal` finally resolves and terminates TLS in one place.** A new service costs one Caddyfile
  entry, because the wildcard already points at the proxy.
- **One failure domain.** If LXC 216 is down, names stop resolving *and* the proxy is gone. Accepted:
  with a single resolver that was already true, and HA at a dozen records is not worth a second guest.
- **A .NET runtime on the guest.** Technitium costs roughly 100–200 MB resident; the guest is sized
  accordingly (≈512 MB) and the `pve` node stays within its 8 GB budget.
- **The CA becomes load-bearing.** Caddy obtains and renews from LXC 215; a CA outage does not stop the
  proxy from starting with existing certificates, but first issuance needs it.
- **DNS is now a dependency of everything**, including the guest's own resolution — which is why it
  runs as an ordered systemd unit rather than inside a container daemon.
- **`.216` is consumed** from the `21x` guest block; `.213` remains free.
- **Existing held work is unchanged** — k3s ([ADR 22](22-k3s-arc-homelab.md)) and the OPNsense router
  ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)) still land later and slot into this
  design (ingress VIP record; DHCP DNS hand-out).

### Alternatives Considered

- **Unbound, optionally behind AdGuard Home** — the strongest pure resolver, but a *resolver*, not an
  authoritative server: an `internal.` zone becomes static `local-zone`/`local-data` edits with no API
  or zone UI, and the wildcard needs the `redirect` idiom. It would need a second component for the
  zone and mDNS anyway.
- **CoreDNS** — no zone UI or management API; it earns its place *inside* k3s as the cluster DNS, not
  as the LAN's authoritative server.
- **BIND 9** — full coverage at the cost of zone files, SOA serial discipline and maintenance
  complexity for a dozen records.
- **Docker Compose for both services** — the packaging used by other workloads, but both containers
  would run with host networking (mDNS, client IPs, UFW), so the isolation is nominal while `dockerd`
  and its boot ordering are added. Precedent leans native for a node's own plumbing (`step-ca`,
  NUT, Netdata).
- **Two guests, DNS and proxy separated** — an extra address, role and backup unit for no functional
  gain at this size.
- **Caddy on the OPNsense router** — rejected in [research 39](../research/39-caddy-on-opnsense-rejected.md):
  a second routing layer, unmanaged configuration, and a permanent admin-port shift.
- **Caddy on the edge appliance** — parked with public ingress: it adds a LAN hop for services that do
  not live there, on the guest with the least storage.

---

## References

- [Research 38](../research/38-technitium-dns.md) — resolver comparison, mDNS bridging, Ansible deployment
- [Research 39](../research/39-caddy-on-opnsense-rejected.md) — why the router is not the proxy
- [Research 35](../research/35-private-ca-and-lan-naming.md) — name space and the stack analysis
- [ADR 37](37-lan-name-space-internal.md) · [ADR 38](38-private-ca-hierarchy-and-custody.md) · [ADR 34](34-lan-tls-only.md) · [ADR 31](31-static-address-scheme.md) · [ADR 20](20-caddy-single-routing-layer.md) · [ADR 24](24-edge-ingress-appliance.md)
- [Idea 10](../ideas/10-internal-ca-dns-stack.md) — the stack this implements
- [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) · [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142) · [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) · [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)
