# Reverse Proxy — Caddy with Auto-TLS and Configuration-as-Code

**Date:** 2026-05-29
**Status:** Implemented

---

## Context

Multiple web services on the homelab (Portainer, Gitea, Ollama WebUI, etc.) need a reverse proxy for TLS termination, subdomain-based routing, and unified ingress. The solution must support internal `.home` domains with local TLS certificates and be reproducible from declarative configuration (IaC).

## Decision

Use **Caddy 2** as the reverse proxy, configured via a single `Caddyfile`.

Key factors:
- **Automatic TLS** — Caddy's built-in Internal CA generates and renews certificates for `.home` domains automatically; no Certbot, no manual cert management
- **True CaC** — entire config in one `Caddyfile`; no GUI, no SQLite state, no database — trivial to back up, diff, and version-control
- **Minimal syntax** — a service route is one line (`reverse_proxy service:port`); no boilerplate for headers, websockets, or redirects
- **HTTP/3 (QUIC)** — supported out of the box for low-latency connections
- **Docker-native** — runs as a container, integrates seamlessly with the Compose stack

Rejected alternatives:
- **Nginx Proxy Manager** — GUI-driven with SQLite state; not fully IaC-declarable; harder to reproduce from backup
- **Traefik** — powerful but over-engineered for a single-node Compose stack; designed for dynamic backend discovery in swarm/k8s
- **Plain Nginx** — requires manual SSL cert management; more config boilerplate per service

## Consequences

- Adding a new proxied service is a one-line addition to `Caddyfile` — rapid onboarding
- Caddy's `Caddyfile` is the single source of truth for routing; changes require a compose restart (`docker compose restart caddy`)
- Internal CA certificates are trusted only on devices that import the CA root — browsers will show "untrusted" warnings for `.home` domains until the CA is added to the trust store
- No separate management UI — all changes are file-based; suitable for CLI/SSH-only operation
