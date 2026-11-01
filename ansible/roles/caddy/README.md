# caddy

Caddy as the single LAN reverse proxy and ACME client for the fleet `step-ca`
([ADR 20](../../../docs/decisions/20-caddy-single-routing-layer.md), [ADR 40](../../../docs/decisions/40-internal-dns-proxy-edge.md)).
Extracted from `edge_host` so the routing layer can run wherever it is needed (e.g. k3s ingress).

- `tasks/main.yml` — apt repository, fleet root from Key Vault, Caddyfile, systemd ordering, enable,
  CA monitor.
- `templates/Caddyfile.j2` — one site per `caddy_sites` entry, TLS-ALPN-01 only, no redirects.
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
| `caddy_sites` | `dns`, `netdata`, `logs`, `proxmox`, `omv` | `name` + `upstream`, optional `tls_skip_verify`. |
| `caddy_after_service` | `dns.service` | Systemd unit Caddy starts after. |
| `caddy_require_technitium` | `true` | Refuse to run when the local resolver role is absent. |
| `caddy_ca_health_url` | `https://ca.internal:9000/health` | Health endpoint the monitor probes. |
| `caddy_leaf_expiry_check_min_remaining_seconds` | `21600` | Fail the check below this much leaf lifetime (6 h). |

## Behaviour

- **HTTPS only** — `auto_https disable_redirects`, TLS-ALPN-01, no `:80` listener and no redirect.
- **TLS-ALPN-01 only** — HTTP-01 would need `80/tcp` from the CA guest; the fallback is documented in runbook 37.
- **Backend certificates are irrelevant** — `tls_skip_verify` covers Netdata, VictoriaLogs and the
  Proxmox UI; the client-facing leg is always a `step-ca` leaf.
- **Expiry is monitored, not just logged** — `homelab-leaf-expiry-check.timer` reads the certificate
  each site actually serves from `127.0.0.1:443` and probes the CA's `/health`; it exits non-zero
  below the threshold, so the failed unit raises the stock Netdata
  `systemd_service_unit_failed_state` alarm (the pattern from runbook 40). A `>24 h` outage expires
  every leaf and no longer passes silently.

---

[← Roles](../README.md)
