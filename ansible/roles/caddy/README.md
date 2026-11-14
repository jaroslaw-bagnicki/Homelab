# caddy

Caddy as the single LAN reverse proxy and ACME client for the fleet `step-ca`
([ADR 20](../../../docs/decisions/20-caddy-single-routing-layer.md), [ADR 40](../../../docs/decisions/40-internal-dns-proxy-edge.md)).
Extracted from `edge_host` so the routing layer can run wherever it is needed (e.g. k3s ingress).

- `tasks/main.yml` — apt repository, fleet root from Key Vault, Caddyfile, systemd ordering, enable,
  CA monitor.
- `templates/Caddyfile.j2` — one site per `caddy_sites` entry (TLS-ALPN-01 only, no redirects) plus the `caddy_public_sites` public zone (plain `http://` blocks on loopback :80, reached via the cloudflared tunnel, ADR 53).
- `templates/homelab-leaf-expiry-check.j2` — hourly probe of the CA health and of the leaf each site
  serves.
- `handlers/main.yml` — reload on Caddyfile change, restart on root-certificate or unit change.
- `vars/main.yml` — role constants (Caddyfile path, CA-root path).

## Parameters

| Variable | Default | Meaning |
|---|---|---|
| `caddy_enabled` | `true` | Deploy Caddy. |
| `caddy_ca_url` | `https://ca.internal:9000/acme/acme/directory` | ACME directory of the private CA. |
| `caddy_keyvault_name` | `homelab-bysxdb-kv` | Vault holding the CA root. |
| `caddy_ca_root_secret_name` | `ca-root-cert` | Secret name. |
| `caddy_ca_root` | `""` | Override to skip the AKV lookup (tests). |
| `caddy_sites` | `dns`, `netdata`, `logs`, `proxmox`, `omv` | `name` + `upstream` (or `upstreams` list), optional `lb_policy`, `health_uri`/`health_interval`/`health_timeout`/`fail_duration`/`max_fails`, and `tls_skip_verify`. |
| `caddy_public_sites` | `[]` | Public zone (ADR 53): `name` (may be a wildcard) + `upstream` origin, rendered as `http://` blocks on loopback :80 for the cloudflared tunnel. |
| `caddy_after_service` | `dns.service` | Systemd unit Caddy starts after. |
| `caddy_require_technitium` | `true` | Refuse to run when the local resolver role is absent. |
| `caddy_ca_health_url` | `https://ca.internal:9000/health` | Health endpoint the monitor probes. |
| `caddy_leaf_expiry_check_min_remaining_seconds` | `21600` | Fail the check below this much leaf lifetime (6 h). |

## Behaviour

- **HTTPS only** — `auto_https disable_redirects`, TLS-ALPN-01, no `:80` listener and no redirect.
- **TLS-ALPN-01 only** — HTTP-01 would need `80/tcp` from the CA guest; the fallback is documented in runbook 37.
- **Backend certificates are irrelevant** — `tls_skip_verify` covers Netdata, VictoriaLogs and the
  Proxmox UI; the client-facing leg is always a `step-ca` leaf.
- **One upstream by default, a list when a site needs failover** — `upstream` is the single-backend
  form; `upstreams` takes a list and pairs with `lb_policy`. `proxmox.internal` uses
  `lb_policy first` over `pve1` then `pve2`: the Proxmox UI is node-scoped, so round-robin would move
  a session between nodes, while `first` keeps it on the primary and only fails over when the primary
  fails its health check. Cluster-wide tickets make the switch transparent.
- **`lb_policy` alone does not fail over** — Caddy's passive checks are off by default
  (`fail_duration` 0), so a dead primary is never demoted. Any site using `lb_policy` must also set
  `health_uri` (which enables the active checker) and, for the passive side, `fail_duration` +
  `max_fails`. Verified 2026-11-07 by stopping `pveproxy` on `pve1`: the proxy kept serving from
  `pve2` and recovered when `pve1` came back.
- **Expiry is monitored, not just logged** — `homelab-leaf-expiry-check.timer` reads the certificate
  each site actually serves from `127.0.0.1:443` and probes the CA's `/health`; it exits non-zero
  below the threshold, so the failed unit raises the stock Netdata
  `systemd_service_unit_failed_state` alarm (the pattern from runbook 40). A `>24 h` outage expires
  every leaf and no longer passes silently.

---

[← Roles](../README.md)
