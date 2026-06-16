# Local DNS Resolution — DNSMasq with Wildcard `.home` Domains

**Date:** 2026-05-29
**Status:** Implemented

---

## Context

Services on the homelab (Caddy, Portainer, Gitea, etc.) need to be addressable by hostname from client devices on the local network. Using IP addresses and port numbers is impractical for multiple services. A local DNS solution is needed that supports wildcard subdomain resolution to a single server IP.

## Decision

Run **DNSMasq in Docker** as the local DNS forwarder, configured with a single wildcard rule mapping `*.home` to the homelab server IP (`192.168.2.200`).

Key factors:
- **Wildcard routing** — a single `address=/.home/192.168.2.200` rule resolves any `*.home` subdomain to the server
- **Lightweight** — single container, minimal memory, no database
- **Built-in caching** — cache-size=2000 reduces upstream query frequency
- **IaC-friendly** — one `dnsmasq.conf` file and one docker-compose service; fully reproducible
- **Upstream forwarding** — queries for non-`.home` domains are forwarded to router, Cloudflare, and Google

Rejected alternatives:
- **Pi-hole** — excellent DNS sink but focused on ad-blocking; more configuration for pure local resolution without blocking
- **Editing each client's `/etc/hosts`** — not scalable; every new service requires client-side changes
- **Router-level DNS** — depends on ISP router capabilities; not programmatically configurable via IaC

Implementation details:
- Must disable Ubuntu's `systemd-resolved` (occupies port 53) before DNSMasq can bind to it
- `domain-needed` and `bogus-priv` prevent forwarding short names and private IP ranges upstream
- `all-servers` enables parallel upstream queries for faster resolution

## Consequences

- Any new service gets a hostname by convention: `service.home` resolves automatically with zero config
- Client devices must use the homelab as their DNS server (or a forwarder pointing to it) for `.home` resolution to work
- Single point of failure — if DNSMasq goes down, local name resolution breaks; client DNS fallback mitigates external access loss
- `systemd-resolved` must remain disabled on the host — only one DNS resolver can bind port 53
