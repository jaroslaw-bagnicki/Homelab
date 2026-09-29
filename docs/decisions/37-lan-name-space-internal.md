# LAN Name Space Is `.internal` — DNSMasq and `.home` Retired

**Date:** 2026-09-29
**Status:** Accepted

---

## Context

[ADR 06](06-local-dns-dnsmasq.md) put the LAN behind **DNSMasq** with a wildcard `*.home` rule
pointing at `192.168.2.200`. Two things have since invalidated it:

- **DNSMasq is gone.** It was deliberately **not reinstalled** during the M910q OS refresh
  ([runbook 25](../runbooks/25-m910q-os-refresh.md)), which moved DNS, Caddy and the Cloudflare tunnel
  off that host. Nothing in the fleet resolves `.home` today — the decision was dead in practice but was
  never recorded as retired.
- **`.home` has no standing.** ICANN rejected `.home` as a gTLD in the 2012 round — its name-collision
  analysis found millions of devices already using it internally — but IETF never gave it special-use
  status in any RFC; RFC 8375 created `.home.arpa` *instead of* it. A name with neither a standard nor a
  guarantee is the wrong foundation to issue certificates for.

That matters now because [ADR 34](34-lan-tls-only.md) requires every LAN service to serve TLS and defers
the certificate question to [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126): a private CA
has to issue for *some* name space, and that name must be settled first
([research 35](../research/35-private-ca-and-lan-naming.md)).

## Decision

**The LAN name space is `.internal`** — the gTLD ICANN reserved in 2024 for private internal use, and
guaranteed never to be delegated publicly.

- **DNSMasq and `.home` are retired** with [ADR 06](06-local-dns-dnsmasq.md), and the DNSMasq runbook
  ([runbook 03](../runbooks/03-dns.md)) is retired with it.
- **This ADR does not replace the DNS service.** Nothing resolves `.internal` yet: name resolution
  returns with the internal service stack — resolver + reverse proxy + private CA — tracked in
  [idea 10](../ideas/10-internal-ca-dns-stack.md) and [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).
  What this ADR settles is the **name space** that stack must serve.
- **Services are planned as `<service>.internal`** (`netdata.internal`, `nas.internal`, …), and their
  certificates come from the fleet private CA once [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) lands.

## Consequences

- One name space for services, certificates and monitoring across the fleet; the `.home` examples that
  remain in docs and in the retired runbooks are historical records, not plans.
- **A resolution gap is open until the stack lands.** With DNSMasq gone and no replacement deployed the
  fleet has no LAN name resolution at all — nodes are reached by static IP
  ([ADR 31](31-static-address-scheme.md)) and by mDNS `.local` names, which is why nothing has broken.
  This is a real gap, not a deferred nicety: it is the reason the stack in idea 10 is worth building.
- **The host placement of that stack is not decided here** — the candidates are `pve` (Docker Compose in
  an LXC), `edge` (bare metal) and `lab` (k3s workload, blocked until k3s lands).
- **Live configuration is repointed with the stack, not before**: the NAS still carries the old domain
  (OMV `nas`, [runbook 32 §3](../runbooks/32-beetle-m3-omv-setup.md)). The `edge_host` role's
  search-domain note is updated alongside this ADR.
- A **public subdomain of the owned domain** remains available as a fallback if client trust for a
  private root proves impractical ([#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)); it is
  not mutually exclusive with `.internal`.

### Alternatives Considered

- **`.home.arpa`** (RFC 8375) — the standard name space for home networks and the source thread's own
  recommendation for a homelab. Rejected by the operator: it is a **second-level** name and too long for
  everyday use, where `.internal` is a single label.
- **`.home`** (status quo, ADR 06) — rejected: no RFC special-use status, no ICANN reservation, and its
  service was already gone.
- **`.lan`** — no RFC and no ICANN reservation. Ubiquitous in consumer routers and firmware, which makes
  it *look* standard without being so.
- **A subdomain of the owned public domain** (`internal.<domain>`) — publicly trusted TLS with no client
  configuration, at the cost of publishing internal hostnames in a public zone. Kept as a fallback rather
  than adopted (see Consequences).
- **`.local`** — reserved for mDNS by RFC 6762 and unusable in a unicast resolver (Apple devices route
  every `.local` query to mDNS and ignore central DNS). It stays in use for mDNS only.

---

## References

- [ADR 06](06-local-dns-dnsmasq.md) — the superseded Local DNS decision
- [ADR 34](34-lan-tls-only.md) — TLS-only LAN rule; defers the private CA to [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)
- [research 35](../research/35-private-ca-and-lan-naming.md) — the name-space analysis (RFCs, ICANN status, rejected options)
- [idea 10](../ideas/10-internal-ca-dns-stack.md) — the internal DNS + CA + proxy stack this name space is for
- [runbook 25](../runbooks/25-m910q-os-refresh.md) — where DNSMasq, Caddy and the tunnel left the M910q
