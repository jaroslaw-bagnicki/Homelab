# Internal DNS and Reverse Proxy — Technitium + Caddy on the Edge Node

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

- **Public ingress is on hold** pending a remote-access decision (VPN, possibly Tailscale). That
  leaves the edge appliance built for Cloudflare Tunnel + Caddy ([ADR 24](24-edge-ingress-appliance.md))
  provisioned but idle — and it is the box ADR 24 already assigns **DNS, the reverse proxy and
  `.internal` routing** to.
- **The router is not the proxy.** Running Caddy on OPNsense is technically possible but rejected
  ([research 39](../research/39-caddy-on-opnsense-rejected.md)).
- **The resolver choice was open.** [Research 35 §6](../research/35-private-ca-and-lan-naming.md) left
  DNSMasq / Unbound / AdGuard Home / BIND 9 open; [research 38](../research/38-technitium-dns.md)
  compares them against a fleet that needs an authoritative `internal.` zone, a k3s registration path
  and an mDNS bridge, and lands on Technitium DNS.

The edge node is ready for the role: Debian 13 on the 7.8 GB eMMC with **3.7 GB free on `/`** and
~1.3 GB of RAM available (measured 2026-10-17), journald set to volatile, no swap, and a proven
full-image backup/restore path ([runbook 27](../runbooks/27-edge-backup-restore.md)).
[Idea 10](../ideas/10-internal-ca-dns-stack.md) already framed the stack as **resolver + proxy + CA**
in one place; this ADR fixes what the two new pieces are and where they run.

## Decision

**Run Technitium DNS and Caddy natively on the `edge` node, and make it the LAN's name-resolution and
routing entry point.**

- **`edge` (`192.168.2.240`)** — the Wyse 3040 already provisioned for ingress
  ([ADR 24](24-edge-ingress-appliance.md), [runbook 24](../runbooks/24-edge-appliance.md)). No new
  guest is created; the node takes the role it was built for.
- **The hostname stays `edge`.** [ADR 33](33-fleet-node-hostnames.md) names a node by its role, and the
  role is ingress — the services it runs are named in the zone (`edge.internal`, `*.internal`), not in
  the hostname. Nothing in the inventory, the playbooks or `host_vars` is renamed.
- **Technitium DNS** is authoritative for `internal.` and the fleet's resolver: a wildcard
  `*.internal` → `.240`, static `A` records for nodes and services, recursive/forwarded upstream over
  **DoT**. Zone changes go through its REST API, driven by Ansible; the admin password comes from Key
  Vault. **Query logging stays off the eMMC** — the zone database is the only write path that matters.
- **Caddy** is the **single LAN reverse proxy** ([ADR 20](20-caddy-single-routing-layer.md)), with its
  Caddyfile in the repo and rendered by Ansible. It serves `https://<service>.internal` and forwards to
  the service's real address on the LAN — and it is already in place if the public tunnel decision
  reverses, so both planes share one proxy.
- **Certificates come from `step-ca` in LXC 215** on `pve` over ACME, starting with **per-service
  leaves** (HTTP-01). A `*.internal` wildcard via DNS-01 is a later optimisation, not a prerequisite;
  root distribution to clients stays [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144).
- **Native systemd units, not a Docker Compose stack.** Both services need host-level networking —
  real client IPs, mDNS visibility, and UFW as the only firewall (a Docker-published port bypasses it,
  the trap already recorded for the VictoriaLogs workload) — so a container adds a daemon and a boot
  ordering dependency without adding isolation. On this box it also keeps the write path off the eMMC.
- **The node's own resolver is Technitium on `127.0.0.1`** (and in `edge_dns_search`), so
  `ca.internal` and every other in-fleet name resolves on the box that needs them.
- **UFW** allows `53`/`443` from `192.168.2.0/24` and the Technitium API only from the fleet; nothing
  is opened to the internet — the public plane stays closed until the remote-access decision.
- **mDNS bridging is optional and later.** All nodes are Ansible-managed and statically addressed, so
  static records cover the fleet; Technitium's mDNS app is adopted only if discovery of
  DHCP/mobile devices becomes useful.
- **Backup is the full-image path plus reproducible state** — runbook 27's eMMC image, with the DNS
  zone exported and the Caddyfile in the repo, so the box reconstructs from Ansible either way.
- **Out of scope here:** DHCP DNS hand-out (the mesh gateway today, OPNsense later — clients adopt the
  resolver per-device meanwhile), k3s service registration (`*.internal` wildcard to the ingress VIP
  first, ExternalDNS once k3s exists), and remote access (Tailscale split DNS pointing at this resolver
  if that route is chosen).

The **CA stays on `pve`** (the TPM requirement of [ADR 38](38-private-ca-hierarchy-and-custody.md)) and
is reached as `ca.internal` → `.215`. Caddy depends on it for issuance only; serving existing
certificates does not need `pve`.

## Consequences

- **`.internal` finally resolves and terminates TLS on the box already assigned to ingress.** A new
  service costs one Caddyfile entry, because the wildcard already points at the proxy.
- **`pve` maintenance no longer takes the fleet's naming down.** Reboots of the hypervisor that hosts
  the CA, VictoriaLogs and Netdata leave names resolving; only `pve`-hosted backends fail.
- **One proxy serves both planes.** If the public tunnel decision reverses, Caddy is already in the
  right place — one Caddyfile, one routing layer ([ADR 20](20-caddy-single-routing-layer.md)).
- **The edge box becomes the fleet's single naming dependency** — and the future public ingress. An
  eMMC failure takes both planes out; recovery is runbook 27's image plus Ansible, and the zone must
  stay exported for that reason.
- **eMMC discipline is now a hard constraint** — query logging off, journald already volatile, no
  swap, a small zone database. The box is fanless and write-light by design; the DNS server must not
  change that.
- **2 GB of RAM is shared with any future cloudflared and Netdata child.** Technitium + Caddy sit at
  roughly 250–300 MB against ~1.3 GB available today, so the ceiling holds, but it is a ceiling to
  watch.
- **No new guest** — the `21x` block remains available for VMs/LXCs.
- **The CA remains on `pve`** — issuance needs `pve` up; serving does not. A `ca.internal` record
  points at `.215`.
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
  NUT, Netdata); on the eMMC it also adds image layers to rewrite and prune.
- **An LXC on `pve`** — the alternative considered first. Rejected: it couples DNS to
  the hypervisor that hosts the CA and is rebooted for Proxmox and HA work, so every `pve` reboot would
  drop naming fleet-wide; it creates a second ingress location that would need migrating back if the
  tunnel returns; and the LXC/PBS boundary buys less than the full-image restore already available on
  the edge box. Remains the fallback if the Wyse 3040 proves unfit.
- **Splitting DNS and proxy across `pve` and `edge`** — two wildcard targets, two backup units and two
  routing configs for one function; the split re-creates the two-layer problem.
- **Caddy on the OPNsense router** — rejected in [research 39](../research/39-caddy-on-opnsense-rejected.md):
  a second routing layer, unmanaged configuration, and a permanent admin-port shift.

---

## References

- [Research 38](../research/38-technitium-dns.md) — resolver comparison, mDNS bridging, Ansible deployment
- [Research 39](../research/39-caddy-on-opnsense-rejected.md) — why the router is not the proxy
- [Research 35](../research/35-private-ca-and-lan-naming.md) — name space and the stack analysis
- [Runbook 24](../runbooks/24-edge-appliance.md) — the edge appliance and its Caddy/DNS target state · [runbook 27](../runbooks/27-edge-backup-restore.md) — full-image backup/restore
- [Research 28](../research/28-wyse3040-hardware-diagnostic.md) — Wyse 3040 hardware and eMMC health
- [ADR 37](37-lan-name-space-internal.md) · [ADR 38](38-private-ca-hierarchy-and-custody.md) · [ADR 34](34-lan-tls-only.md) · [ADR 31](31-static-address-scheme.md) · [ADR 20](20-caddy-single-routing-layer.md) · [ADR 24](24-edge-ingress-appliance.md)
- [Idea 10](../ideas/10-internal-ca-dns-stack.md) — the stack this implements
- [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) · [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142) · [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) · [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)
