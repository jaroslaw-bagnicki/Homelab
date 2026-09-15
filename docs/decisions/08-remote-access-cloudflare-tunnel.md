# Remote Access — Cloudflare Tunnel for Inbound HTTPS

**Date:** 2026-05-30
**Status:** Superseded by [ADR 19 — Cloudflare Tunnel HTTP origin with Caddy reverse proxy on Cloudlab](19-cloudflare-tunnel-http-origin.md)

---

## Context

The homelab sits behind a CGNAT ISP (Poland residential) — no public IPv4 address, no port forwarding possible. Remote access to web services (Portainer, Gitea, Hermes WebUI) from outside the LAN is needed.

## Decision

Use **Cloudflare Tunnel** (`cloudflared`) for inbound HTTPS access via a custom domain.

Key factors:
- **CGNAT bypass** — `cloudflared` makes a single outbound connection to Cloudflare's edge; no inbound ports, no router config
- **Existing DNS integration** — domain DNS is delegated to Cloudflare; tunnel creates CNAME records automatically for public hostnames
- **Free tier** — unlimited tunnels on Cloudflare's free plan; no per-tunnel cost
- **Zero-trust option** — Cloudflare Access can add authentication before traffic reaches the homelab
- **Auto-TLS** — Cloudflare provides edge certificates automatically; no cert management on the server

Rejected alternatives:
- **Tailscale Funnel** — requires Tailscale on every client device; doesn't integrate with the existing Caddy setup; more overhead for occasional web access from non-personal devices
- **Ngrok** — per-connection rate limits on free tier; no DNS integration; session-based URLs are inconvenient for persistent services
- **Port forwarding via ISP** — not possible on CGNAT; would require a static IP add-on (~30 PLN/month) and eliminate the cost advantage of physical hosting

Architecture:
- `cloudflared` runs as a Docker container in the Compose stack
- Subdomain routing managed in Cloudflare Zero Trust dashboard (public hostname rules)
- Wildcard `*.example.com` → Caddy at `http://caddy:80` — new services need only a Caddyfile entry and a `docker compose restart caddy`; no tunnel config changes or DNS record needed
- Target containers must be on the `homelab_net` Docker network to be reachable by name
- Caddy public-domain site blocks use the `http://` prefix because Cloudflare terminates TLS at its edge and forwards plain HTTP through the tunnel — without it, Caddy's automatic HTTPS redirect creates an infinite loop

## Consequences

- All external traffic routes through Cloudflare — single point of trust and latency hop
- Services are accessible from anywhere without VPN; useful for casual access but means services are internet-exposed (mitigated by Cloudflare Access policies)
- Tunnel token (long-lived credential) must be stored securely — compromised token allows tunnel impersonation until revoked
- Caddy handles internal `.home` traffic; Cloudflare tunnel handles external `example.com` traffic — two parallel ingress paths

## Superseded by ADR 19

The original V1 design sends plain HTTP from cloudflared to Caddy (CF edge terminates TLS, then forwards plain HTTP through the tunnel). This design has known weaknesses:

- **No end-to-end TLS** between CF edge and the origin web server — defense in depth is reduced
- **CF SSL mode downgrade** required: "Full (Strict)" is not possible with a plain-HTTP origin; the "Full" mode is required instead, which accepts any cert (including self-signed)
- **Inconsistent with ADR 07** (Caddy as the reverse proxy) — Caddy can terminate TLS; making it do so aligns the architecture

[ADR 19](19-cloudflare-tunnel-http-origin.md) replaces this design for **all** new deployments — but not by adding TLS between cloudflared and Caddy. ADR 19 settled the opposite: the tunnel remains the only ingress path and the cloudflared → Caddy hop stays **plain HTTP** (`http://caddy:80`), because the HTTPS-origin attempt failed on an SNI mismatch (`cloudflared` presents SNI `caddy`, which the Origin CA certificate's SANs did not cover) with no dashboard or config-file override available.

The weaknesses listed above are therefore accepted rather than removed, and compensated differently:

- **Tunnel-only ingress** — UFW denies inbound TCP/80 and TCP/443; direct public-IP exposure is not used.
- **Routing consolidated in Caddy** — per-service hostnames live in the Caddyfile, not the Cloudflare dashboard ([ADR 20](20-caddy-single-routing-layer.md)).
- **The origin hop stays private** — cloudflared and Caddy communicate over the `homelab_net` Docker bridge network, which is what the design leans on instead of origin TLS.

Rejected along the way: Caddy-issued Let's Encrypt over ACME HTTP-01 or DNS-01, a self-signed origin certificate, and direct public-IP exposure.

The physical Homelab (M910q) still runs the V1 arrangement; its migration to the ADR 19/20 pattern is the edge-ingress work in [ADR 24](24-edge-ingress-appliance.md).

## References

- [ADR 07 — Reverse Proxy: Caddy with Auto-TLS and Configuration-as-Code](../decisions/07-reverse-proxy-caddy.md)
- [ADR 19 — Cloudflare Tunnel HTTP origin with Caddy reverse proxy on Cloudlab](19-cloudflare-tunnel-http-origin.md) (replacement)
