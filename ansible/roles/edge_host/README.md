# edge_host

Extras for the Edge Wyse 3040 ingress appliance ([ADR 24](../../../docs/decisions/24-edge-ingress-appliance.md)) — now also the LAN's name-resolution and routing entry point: **Technitium DNS** and **Caddy** run natively on the box ([ADR 40](../../../docs/decisions/40-internal-dns-proxy-edge.md)).

## Files

- `defaults/main.yml` — role parameters, records, Technitium settings and Caddy sites.
- `tasks/main.yml` — base eMMC discipline, then the Technitium, resolver and Caddy imports.
- `tasks/technitium.yml` — .NET runtime, portable app, systemd unit, REST-driven zone/settings/records, AKV admin password.
- `tasks/resolver-prepare.yml` — stop `systemd-resolved`, remove its stub symlink, and keep a transient upstream while Technitium starts.
- `tasks/resolver.yml` — `127.0.0.1` / `internal` resolver configuration.
- `tasks/caddy.yml` — Caddy apt repository, fleet CA root, Caddyfile and systemd ordering.
- `templates/dns.service.j2` — native Technitium unit.
- `templates/Caddyfile.j2` — LAN sites, all issuing from `step-ca`.
- `handlers/main.yml` — journald, Technitium, Caddy reload/restart.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `edge_host_dns_search` | `internal` | Search suffix written to `/etc/network/interfaces` and `/etc/resolv.conf`. |
| `edge_host_dns_nameservers` | `[127.0.0.1]` | Technitium listens locally; `edge` must resolve through it. |
| `edge_host_bootstrap_nameservers` | `[1.1.1.1, 8.8.8.8]` | Transient upstream only while `systemd-resolved` is being replaced. |
| `edge_host_technitium_enabled` | `true` | Deploy the DNS service. |
| `edge_host_technitium_install_dir` | `/opt/technitium/dns` | Portable app directory. |
| `edge_host_technitium_config_dir` | `/etc/dns` | Zone database and server configuration. |
| `edge_host_technitium_admin_secret_name` | `technitium-admin-password` | AKV secret holding the admin password. |
| `edge_host_technitium_admin_password` | `""` | Override to skip the AKV lookup (tests). |
| `edge_host_technitium_forwarders` | Cloudflare + Quad9 | DoT upstreams; IP + name keeps bootstrap off the local resolver. |
| `edge_host_technitium_records` | fleet `A` records + `*.internal` | Explicit `ca.internal` → `.215`, wildcard → `.240`. |
| `edge_host_technitium_upgrade` | `false` | Opt-in portable-app/runtime refresh. |
| `edge_host_caddy_enabled` | `true` | Deploy the proxy. |
| `edge_host_caddy_ca_url` | `https://ca.internal:9000/acme/acme/directory` | step-ca ACME directory. |
| `edge_host_caddy_ca_root_secret_name` | `ca-root-cert` | AKV secret with the fleet root. |
| `edge_host_caddy_sites` | `netdata.internal` | One Caddyfile site per service; all use TLS-ALPN-01. |

## Notes

- **eMMC discipline** — journald is volatile, Technitium query logging is off, stats stay in memory, the cache is not saved to disk, and logs go to journald. The zone database is the only meaningful write path.
- **ADRs 34/40** — Caddy validates through TLS-ALPN-01 on `443`; HTTP-01 is disabled and TCP/80 stays closed.
- **Certificates** — every Caddy site obtains a short-lived leaf from `step-ca` in LXC 215 through `ca.internal`; the ACME client trusts the fleet root from AKV.
- **Bootstrap** — the host resolver is switched to Technitium only after the service answers, so the play does not cut its own DNS during provisioning.
- **Backend hop** — the `netdata.internal` site currently reaches Netdata's self-signed HTTPS backend with `tls_insecure_skip_verify`; the client-facing leg is already the step-ca leaf. [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) removes the backend self-signed hop.
- Applied by `playbook-edge.yml`; hostname/UTC/Avahi come from `common`, UFW/fail2ban/sshd from `security`.

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
