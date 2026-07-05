# HTTPS-only origin via Cloudflare Tunnel + Cloudflare Origin CA on Cloudlab

**Date:** 2026-07-05
**Status:** Accepted

---

## Context

Cloudlab (Contabo VPS) needs HTTPS ingress matching Homelab's pattern (ADR 08 — Cloudflare Tunnel for inbound HTTPS). The originally planned approach (issue #14, ADR-implied) was direct public IP exposure with Caddy's built-in ACME for Let's Encrypt (issue #24). That approach:

- Requires port 80 publicly reachable (not always possible — CGNAT, restrictive ISPs)
- Mixes public CA validation with a private VPS
- Doesn't match Homelab's pattern (ADR 08), making the two environments diverge

Issue #25 introduces a Cloudflare Tunnel on Cloudlab (separate from Homelab's `homelab-tunnel`) using a different external DNS scope (`ctb.cloud5.ovh` vs Homelab's `*.cloud5.ovh`). With Tunnel, CF edge terminates TLS from clients; the connection from cloudflared to Caddy is internal (Docker network). This changes the trust model and the cert requirements.

## Decision

- **cloudflared** is deployed by the Ansible `docker_services` role as a fourth container alongside portainer, caddy, hello
- **Cloudflare Tunnel** is the only public ingress path; direct public IP exposure is not used
- Caddy uses a **Cloudflare Origin CA certificate** for TLS to origin (not Let's Encrypt, not self-signed, not Caddy-issued)
- **CF SSL/TLS mode: Full (Strict)** — required so CF edge validates the Origin CA cert on origin
- **Caddy binds 127.0.0.1:443 only** (loopback); no external port 80/443/8080 binding. Loopback-only 8080 is used for a local debug endpoint
- **Caddyfile serves HTTPS only** (no `http://` block). Per-host site blocks reference the Origin cert explicitly via the `tls` directive (no ACME attempt)
- **UFW denies inbound 80** (defense in depth — tunnel handles all public traffic)
- **UFW allows outbound UDP/7844** (cloudflared's QUIC connection to CF edge)
- **CF edge "Always Use HTTPS"** is enabled — public HTTP requests get 301-redirected to HTTPS at CF edge, before reaching the tunnel

The cert is provisioned once in the CF dashboard (SSL/TLS → Origin Server → Create Certificate) and the PEM + private key are stored in Azure Key Vault `homelab-bysxdb-kv` as secrets `cloudflared-origin-cert-cloudlab` and `cloudflared-origin-key-cloudlab`. Validity: 15 years. No renewal automation needed.

## Alternatives considered

- **Let's Encrypt via ACME HTTP-01** (issue #24) — rejected. Requires port 80 publicly reachable; doesn't match ADR 08 pattern; Caddy would need public CA validation that we have no reason to require.
- **Let's Encrypt via ACME DNS-01 (Cloudflare DNS plugin)** — rejected for now. Caddy can issue + auto-renew its own cert using the CF DNS plugin, but requires a CF API token with DNS-edit permission as a 4th KV secret. More moving parts (token, plugin config, renewal failures to debug) for no benefit over the static Origin CA approach. Revisit if the project ever outgrows the static cert.
- **Self-signed cert** — rejected. Caddy would issue its own internal CA cert; clients would see untrusted-cert errors; not viable for production-like use.
- **Direct public IP exposure (no tunnel)** — rejected. Doesn't match ADR 08 pattern; exposes the VPS IP; loses the CGNAT-bypass benefit if VPS IP ever changes.

## Consequences

- All public HTTPS traffic terminates at CF edge; clients see CF's public edge cert (trusted)
- Caddy presents the CF Origin CA cert to cloudflared (over the Docker network, not visible to external clients)
- Direct-IP testing via SSH port-forward (e.g., `ssh -L 8443:127.0.0.1:443 cloudlab`) requires the `-k` flag — the CF Origin CA is not in the local trust store by default
- Port 80 is not bound externally; CF Tunnel is the only ingress path
- The Origin cert is valid for 15 years — no cert renewal automation, no ACME challenge to debug
- Operator must provision the Origin cert in CF dashboard and store PEM + key in KV before the first Ansible run
- The `cloudflared` container joins the `homelab_net` Docker network — the same network Caddy and other services use, allowing name-based routing within the stack
- All public traffic routes through Cloudflare (single point of trust and latency hop) — consistent with ADR 08
- Future services exposed publicly only need: (a) a new CF public hostname rule, (b) a new Caddyfile site block, (c) a new SAN in the Origin cert

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
