# Caddy as Single Routing Layer on Cloudlab

**Date:** 2026-07-05
**Status:** Accepted

---

## Context

When exposing Portainer CE publicly at `portainer.cloud5.ovh`, the natural
option was to add a dedicated public hostname in the Cloudflare Tunnel
configuration — `portainer.cloud5.ovh → http://portainer:9000` — bypassing
Caddy entirely. The tunnel already does TLS termination at the Cloudflare
edge, so a direct container-to-tunnel route technically removes one network
hop.

The `docker_services` Ansible role, however, already deploys Caddy as the
in-cluster reverse proxy and manages its configuration from version control.
Adding Portainer routing directly in the Cloudflare Zero Trust dashboard
splits routing logic across two places, neither of which can validate the
other. The Caddyfile becomes harder to keep authoritative for cloudlab
public services.

During the implementation, this split also surfaced a Cloudflare Tunnel
ingress behavior: ingress rules match in declaration order (first-match-wins),
not longest-prefix. A `*.cloud5.ovh → http://caddy:80` catch-all rule
positioned before the specific `portainer.cloud5.ovh` rule shadowed it,
sending Portainer traffic to Caddy — which then had no matching site block
and returned an empty 200.

## Decision

**On cloudlab, route every public hostname through Caddy. The Cloudflare
Tunnel is restricted to TLS termination and edge features; it does not
make per-service routing decisions.**

Concretely:

- The tunnel has at most two entries: `cloud5.ovh → http://caddy:80` (or
  via the wildcard `*.cloud5.ovh → http://caddy:80` if a wildcard catch-all
  is preferred) and nothing else. No per-service hostnames.
- All host-to-backend mapping lives in the `Caddyfile.j2` Ansible template
  under `ansible/roles/docker_services/templates/`, driven by `docker_services`
  role defaults.
- Adding a new public service on cloudlab = one new site block in
  `Caddyfile.j2` + re-run playbook. No Cloudflare dashboard change.
- When reverse-proxying to a backend that needs to know the original scheme
  (e.g., Portainer's CSRF check, which compares `Origin` against
  `X-Forwarded-Proto`), use Caddy's `header_up X-Forwarded-Proto https`
  inside the `reverse_proxy` block.

## Consequences

- **Single source of truth for routing.** The Caddyfile is the only place to
  read or change to understand what traffic goes where on cloudlab. Diffable,
  reviewable, reproducible from a fresh deploy.
- **No dashboard churn.** Adding a service does not require opening the
  Cloudflare Zero Trust dashboard, finding the right tunnel, or worrying
  about ingress rule order.
- **Testable via Ansible.** A new `Caddyfile.j2` block can be validated by
  running `ansible-playbook --check --diff` against cloudlab before the
  change goes live.
- **One extra network hop on the docker network.** Internal-to-docker latency
  for an L7 reverse proxy is negligible (single-digit milliseconds), and the
  hop stays on the same `homelab_net` bridge network.
- **The wildcard-tunnel rule becomes the only routing decision on the edge
  side.** If that rule is ever removed, hostname routing breaks entirely —
  a future maintainer must preserve at least one wide-enough tunnel entry.
- **Backend services must trust the proxy.** Any backend that does
  origin/protocol validation (Portainer's CSRF, GitLab's trusted proxies,
  etc.) must receive the right forwarded headers from Caddy. Document
  this requirement alongside each new service.

### Alternatives Considered

- **Direct tunnel per service.** Each public hostname gets its own tunnel
  entry pointing to the backend. Removes one hop but splits routing across
  Cloudflare dashboard + Caddyfile. Harder to keep in sync and to test
  changes locally. Chosen against because this project values
  configuration-as-code over per-hop efficiency.
- **One Caddy site block per tunnel entry.** Duplicate effort — every tunnel
  hostname would need both a tunnel entry and a Caddy site block. Worse
  than either option above.
- **Rely on wildcard tunnel only and let Caddy route everything via Host
  header.** Effectively the chosen path. Considered the same option until
  the ingress-shadowing incident confirmed the value of explicit
  documentation rather than implicit understanding.
