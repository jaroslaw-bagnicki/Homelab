# technitium

Technitium DNS Server as a native systemd service — authoritative for the LAN zone, the fleet
resolver, and the ACME prerequisite for the private CA ([ADR 40](../../../docs/decisions/40-internal-dns-proxy-edge.md)).
Extracted from `edge_host` so the server can run on any node.

- `tasks/technitium.yml` — .NET runtime, portable app, hardened unit, REST-driven zone/settings/records, AKV admin password.
- `tasks/resolver-prepare.yml` — stop `systemd-resolved`, drop its stub symlink, keep a transient upstream while the service starts.
- `tasks/resolver.yml` — point `/etc/resolv.conf` and `/etc/network/interfaces` at `127.0.0.1` with the zone as search suffix.
- `templates/dns.service.j2` — native unit (`ProtectSystem=strict`, `CAP_NET_BIND_SERVICE` only).
- `vars/main.yml` — role constants (paths, user, loopback API, bootstrap resolvers).

## Parameters

| Variable | Default | Meaning |
|---|---|---|
| `technitium_enabled` | `true` | Deploy the service. |
| `technitium_domain` | `edge.internal` | `dnsServerDomain` reported by the server. |
| `technitium_zone` | `internal` | Authoritative zone; also the host search suffix. |
| `technitium_ttl` | `300` | TTL for the managed `A` records. |
| `technitium_records` | fleet `A` records + `*.internal` | Explicit `ca.internal` → `.215`, wildcard → `.240`. |
| `technitium_forwarders` | Cloudflare + Quad9 | DoT upstreams; IP + name keeps bootstrap off the local resolver. |
| `technitium_forwarder_protocol` | `Tls` | Upstream protocol. |
| `technitium_settings` | see defaults | REST settings applied on every run (recursion scope, stats, cache, API bind). |
| `technitium_keyvault_name` | `homelab-bysxdb-kv` | Vault holding the admin password. |
| `technitium_admin_secret_name` | `technitium-admin-password` | Secret name. |
| `technitium_admin_password` | `""` | Override to skip the AKV lookup (tests). |
| `technitium_portable_sha256` | pinned | SHA-256 of the portable archive; bump deliberately with an app upgrade. |
| `technitium_dotnet_install_sha256` | pinned | SHA-256 of `dotnet-install.sh`; bump with a runtime upgrade. |
| `technitium_upgrade` | `false` | Opt-in re-download of app and runtime. |
| `technitium_manage_host_resolver` | `true` | Rewrite the host resolver to `127.0.0.1`. |
| `technitium_resolv_conf_comment` | management banner | First line written to `/etc/resolv.conf`. |

## Behaviour

- **Idempotent login** — the post-password-change login always runs: a task skipped by `when`
  still assigns its result to `register`, which would hide the successful login from the assert.
- **eMMC discipline** — query logging off, stats in memory, cache not persisted; the zone database
  is the only meaningful write path.
- **API on loopback** — `127.0.0.1:5380`; Caddy publishes the console at `https://dns.internal`.
- **Bootstrap safety** — the host resolver switches to Technitium only after the API answers.

---

[← Roles](../README.md)
