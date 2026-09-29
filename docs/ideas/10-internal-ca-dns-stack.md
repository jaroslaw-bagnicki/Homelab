# Idea 10 — Internal DNS + Private CA + Reverse Proxy Stack

> Give the LAN one **name space**, one **certificate authority** and one **HTTPS entry point**:
> a local resolver answers `*.‹lan-domain›` with the stack's IP, **Caddy** terminates TLS and routes
> by hostname, and **step-ca** issues the certificates as a private ACME server — so every LAN
> service gets a **trusted, self-renewing** certificate instead of a browser warning. Today the fleet
> resolves `*.home` through DNSMasq ([ADR 06](../decisions/06-local-dns-dnsmasq.md)) and terminates
> with Caddy's per-instance internal CA ([ADR 07](../decisions/07-reverse-proxy-caddy.md)) — neither a
> durable name space nor a real fleet trust anchor ([ADR 34](../decisions/34-lan-tls-only.md) defers
> that to [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)).

**Status**: 🧠 Idea — thread archived, nothing decided
**Date**: 2026-09-29
**Source**: [Gemini — pseudo-domains for local networks](https://share.gemini.google/UPNAO3UsBe8l) (published 2026-09-29)
**Related**: [research 35](../research/35-private-ca-and-lan-naming.md) (analysis behind this idea) · [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) (the private-CA ADR this feeds) · [ADR 34](../decisions/34-lan-tls-only.md) · [ADR 06](../decisions/06-local-dns-dnsmasq.md) / [ADR 07](../decisions/07-reverse-proxy-caddy.md) (incumbents) · [ADR 31](../decisions/31-static-address-scheme.md) (a guest on `pve`) · [Idea 07](07-opnsense-futro-s930.md) (alternative host)

---

## Context

[ADR 34](../decisions/34-lan-tls-only.md) made every LAN service TLS-only, then admitted the gap: with
self-signed certificates the transport is encrypted but the server is **unauthenticated** — a LAN MITM
still wins, and users learn to click past warnings. Fixing that needs a **private CA**, which is
[#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126). Two things were left open: what the
certificates are issued **for** (the fleet's `.home` has no standards status), and **what** issues them.
A private CA is only useful if services renew themselves against it, so the natural shape is a single
stack — **resolver + proxy + CA** — which is also where DNS, TLS and naming get decided together
rather than one at a time.

## The stack

```
client ── DNS: grafana.internal → stack IP ──► [ local DNS ]  (Unbound / AdGuard Home)
                                                     │
client ── HTTPS ──────────────────────────────────► [ Caddy ] ──► services (Netdata, Proxmox UI, …)
                                                        │
                                          ACME ◄────────┴──────► [ step-ca ] (private CA)
```

- **One wildcard DNS rule** (`*.‹lan-domain›` → the node's IP) means a new service needs a `Caddyfile`
  entry and nothing else.
- **Caddy** owns TLS termination and hostname routing; **`step-ca`** issues short-lived certificates
  over ACME, which Caddy renews automatically on the internal Docker network.
- Candidate deployment: **one Docker Compose stack in an unprivileged LXC on `pve`** — Proxmox
  snapshots/PBS then back up names, routing rules and the CA's private key as a unit.

## Name space — the options

`*.local` is reserved for mDNS (RFC 6762) and must stay out of a unicast resolver — it breaks
resolution on Apple devices and does not cross subnets. The real candidates:

| Name | Verdict | Reason |
|---|---|---|
| **`.home.arpa`** | Leading candidate | RFC 8375 — the IETF-dedicated name space for home networks; collision-free, and the standard choice for a private resolver |
| **`.internal`** | Leading candidate | Reserved by ICANN (2024) for private use; guaranteed never to be delegated, but the corporate convention rather than the home one |
| Subdomain of the owned public domain | Real contender | Publicly trusted TLS via DNS-01, **zero client configuration** — at the cost of publishing internal hostnames in public DNS and needing internet + provider API at renewal |
| `.home` (incumbent) | Weak | No RFC and no ICANN reservation; kept only because millions of consumer devices use it |
| `.lan` | Rejected | No standard at all, despite ubiquitous router use |

## Host — the options

| Host | Verdict | Reason |
|---|---|---|
| **LXC on `pve`** (operator's lean) | Leading candidate | Snapshot-able, keeps the firewall appliance clean, fits the existing 21x guest scheme |
| OPNsense (Futro S930), native | Weaker | FreeBSD binary works, but the router's XML backup misses the CA data and it adds moving parts to the firewall — and the router is currently **Held** ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)) |
| OPNsense as VM, stack beside it | Cleanest on paper | Unbound stays on the router, CA + proxy stay where backups are easy |
| OPNsense built-in CA | Rejected for now | No ACME **server** — only a client for fetching certificates from outside, so in-lab auto-renewal is lost |

## Open questions

- **Name space**: `.home.arpa` vs `.internal` vs a public subdomain — and how a rename lands on the
  edge/OPNsense DNS ownership tracked in [ADR 06](../decisions/06-local-dns-dnsmasq.md) /
  [ADR 24](../decisions/24-edge-ingress-appliance.md).
- **CA hierarchy and key custody** — [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)
  already sketches offline root / Key Vault intermediate / short-lived leaves; is `step-ca` the tool?
- **One wildcard on the proxy, or per-service leaves?** Simplest operationally, but the same key sits
  in front of every service, and one expiry takes everything down together.
- **Resolver**: Unbound vs AdGuard Home vs dnsmasq.
- **Client trust rollout** — a managed workstation may refuse a private root, and Firefox keeps its
  own trust store.
- **Nothing measured**: RAM/CPU on the Wyse 5070 and the Docker-in-LXC recipe are unverified.

## References

- [research 35 — private CA and LAN domain naming](../research/35-private-ca-and-lan-naming.md) — findings, snippets and the full option analysis
- [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) · [ADR 34](../decisions/34-lan-tls-only.md) · [ADR 06](../decisions/06-local-dns-dnsmasq.md) · [ADR 07](../decisions/07-reverse-proxy-caddy.md)
