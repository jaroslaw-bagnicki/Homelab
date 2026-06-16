# Remote Access — Cloudflare Tunnel for Inbound HTTPS

**Date:** 2026-05-30
**Status:** Implemented

---

## Context

The homelab sits behind a CGNAT ISP (Poland residential) — no public IPv4 address, no port forwarding possible. Remote access to web services (Portainer, Gitea, Hermes WebUI) from outside the LAN is needed.

## Decision

Use **Cloudflare Tunnel** (`cloudflared`) for inbound HTTPS access via a custom domain.

Key factors:
- **CGNAT bypass** — `cloudflared` makes a single outbound connection to Cloudflare's edge; no inbound ports, no router config
- **Existing DNS integration** — domain is registered at Cloudflare; tunnel routes subdomains automatically through Cloudflare's DNS
- **Free tier** — unlimited tunnels on Cloudflare's free plan; no per-tunnel cost
- **Zero-trust option** — Cloudflare Access can add authentication before traffic reaches the homelab
- **Auto-TLS** — Cloudflare provides edge certificates automatically; no cert management on the server

Rejected alternatives:
- **Tailscale Funnel** — requires Tailscale on every client device; doesn't integrate with the existing Caddy setu; more overhead for occasional web access from non-personal devices
- **Ngrok** — per-connection rate limits on free tier; no DNS integration; session-based URLs are inconvenient for persistent services
- **Port forwarding via ISP** — not possible on CGNAT; would require a static IP add-on (~30 PLN/month) and eliminate the cost advantage of physical hosting

Architecture:
- `cloudflared` runs as a Docker container in the Compose stack
- Subdomain routing managed in Cloudflare Zero Trust dashboard (public hostname rules)
- Wildcard `*.example.com` → Caddy at `http://caddy:80` — new services need only a Caddyfile entry and a Cloudflare DNS record; no tunnel config changes

## Consequences

- All external traffic routes through Cloudflare — single point of trust and latency hop
- Services are accessible from anywhere without VPN; useful for casual access but means services are internet-exposed (mitigated by Cloudflare Access policies)
- Tunnel token (long-lived credential) must be stored securely — compromised token allows tunnel impersonation until revoked
- Caddy handles internal `.home` traffic; Cloudflare tunnel handles external `example.com` traffic — two parallel ingress paths
