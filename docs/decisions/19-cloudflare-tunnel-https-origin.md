# Cloudflare Tunnel HTTP origin with Caddy reverse proxy on Cloudlab

**Date:** 2026-07-05
**Status:** Accepted (revised 2026-07-05)

---

## Context

Cloudlab (Contabo VPS) needs HTTPS ingress matching Homelab's pattern (ADR 08 — Cloudflare Tunnel for inbound HTTPS). The originally planned approach (issue #14, ADR-implied) was direct public IP exposure with Caddy's built-in ACME for Let's Encrypt (issue #24). That approach:

- Requires port 80 publicly reachable (not always possible — CGNAT, restrictive ISPs)
- Mixes public CA validation with a private VPS
- Doesn't match Homelab's pattern (ADR 08), making the two environments diverge

Issue #25 introduces a Cloudflare Tunnel on Cloudlab (separate from Homelab's `homelab-tunnel`) using a different external DNS scope (`cloud5.ovh` vs Homelab's `*.cloud5.ovh`). With Tunnel, CF edge terminates TLS from clients; the connection from cloudflared to Caddy is internal (Docker network). This changes the trust model and the cert requirements.

## Decision (revised 2026-07-05)

- **cloudflared** is deployed by the Ansible `docker_services` role as a fourth container alongside portainer, caddy, hello
- **Cloudflare Tunnel** is the only public ingress path; direct public IP exposure is not used
- **cloudflared connects to Caddy via HTTP** (`http://caddy:80`) — TLS is terminated at CF edge; the connection between cloudflared and Caddy is internal Docker network traffic
- **Caddyfile serves plain HTTP** — no TLS, no cert directives. Caddy proxies internal services and serves responses directly
- **Dashboard tunnel config** points all hostnames to `http://caddy:80` — no HTTPS origin URL (eliminates TLS SNI mismatch between `caddy` hostname and cert SANs)
- **UFW denies inbound 80** (defense in depth — tunnel handles all public traffic)
- **UFW allows outbound UDP/7844** (cloudflared's QUIC connection to CF edge)

### Original HTTPS-to-origin approach (superseded)

The original design attempted HTTPS between cloudflared and Caddy using a **Cloudflare Origin CA certificate**. This was abandoned because:

1. **SNI mismatch**: cloudflared connects with TLS SNI=`caddy` (derived from the dashboard ingress rule URL `https://caddy:443`). The cert's SANs cover only `*.cloud5.ovh` and `cloud5.ovh` — not `caddy`.
2. **No config-file override**: cloudflared v2026.6.1 config parser discards `originRequest` fields for dashboard-managed tunnels (`--origin-server-name`, `--no-tls-verify`, and config.yml `originRequest` settings are all ignored).
3. **No dashboard setting**: the CF Zero Trust dashboard does not expose an "Origin Server Name" field for public hostname TLS settings.

After exhausting CLI flags, config files, and dashboard options, the simplest and most reliable solution was to switch the tunnel origin URL to `http://caddy:80` and drop TLS between cloudflared and Caddy entirely. Public traffic remains HTTPS (CF terminates at edge); internal Docker traffic is plain HTTP on a private network.

### Why this is acceptable

- **PUBLIC traffic**: CF edge terminates TLS for all cloud5.ovh hostnames. Clients never see the internal HTTP connection.
- **Internal traffic**: cloudflared and Caddy communicate over the `homelab_net` Docker bridge network. No untrusted parties can intercept traffic on this network.
- **No cert management**: eliminates cert provisioning, renewal, SAN management, KV secret management, and TLS compatibility debugging.
- **Matches ADR 08**: this is the same pattern used for the original Homelab setup (CF terminates TLS, plain HTTP to origin).

## Alternatives considered

- **Let's Encrypt via ACME HTTP-01** (issue #24) — rejected. Requires port 80 publicly reachable; doesn't match ADR 08 pattern; Caddy would need public CA validation that we have no reason to require.
- **Let's Encrypt via ACME DNS-01 (Cloudflare DNS plugin)** — rejected for now. Caddy can issue + auto-renew its own cert using the CF DNS plugin, but requires a CF API token with DNS-edit permission as a 4th KV secret. More moving parts (token, plugin config, renewal failures to debug) for no benefit over the static Origin CA approach. Revisit if the project ever outgrows the static cert.
- **Self-signed cert** — rejected. Caddy would issue its own internal CA cert; clients would see untrusted-cert errors; not viable for production-like use.
- **Direct public IP exposure (no tunnel)** — rejected. Doesn't match ADR 08 pattern; exposes the VPS IP; loses the CGNAT-bypass benefit if VPS IP ever changes.

## Consequences

- All public HTTPS traffic terminates at CF edge; clients see CF's public edge cert (trusted)
- cloudflared connects to Caddy over HTTP on `homelab_net` Docker network (no TLS between origin and proxy)
- Caddyfile is simpler: plain HTTP blocks (no `tls` directives, no cert files to mount)
- No cert provisioning, no cert renewal, no KV cert fetches — only the tunnel token is stored in KV
- The Ansible role fetches a single secret from KV (tunnel token) via `azure.azcollection.azure_keyvault_secret` lookup
- Direct-IP testing via SSH port-forward works on `http://127.0.0.1:8080` (debug endpoint)
- Port 80 is not exposed externally; CF Tunnel is the only ingress path
- All public traffic routes through Cloudflare (single point of trust + latency hop) — consistent with ADR 08
- Future services need only a Caddyfile `http://` block + CF dashboard DNS record (if not covered by wildcard)

## References

- ADR 07 — Reverse Proxy: Caddy with Auto-TLS and Configuration-as-Code
- ADR 08 — Remote Access: Cloudflare Tunnel for Inbound HTTPS
- ADR 10 — Ansible for Host Configuration Management
- ADR 12 — Establish Lightweight ADR Log in MADR Format
- ADR 16 — GH Codespaces Service Principal for Homelab (defines the SP used for KV access from dev container)
- Issue #14 — Ansible docker_services role (portainer, caddy, hello)
- Issue #24 — Let's Encrypt TLS certs (superseded by this decision)
- Issue #25 — Add Cloudflare Tunnel to Cloudlab docker_services stack (this work)
- Runbook 16 — Docker Services Ansible Role (updated with this work)
- Runbook 5 — Cloudflare Tunnel (manual, superseded by runbook 16 + issue #25)
