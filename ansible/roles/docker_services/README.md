# docker_services

Deploys the core Docker Compose stack on `lab` — Portainer, the origin Caddy, and hello — plus the shared bridge networks. The public tunnel is **not** here: it runs bare-metal on `edge` (ADR 24 (2026-11-14 amendment), `cloudflared` role); the edge Caddy proxies the public zone to this stack's origin Caddy on `:8080`. (Migrated from `cloudlab` as-is — #44 intermediate step, runbook 47.)

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — networks, secrets, templates, Compose up, Portainer bootstrap.
- `handlers/main.yml` — restart Caddy, redeploy the stack.
- `templates/docker-compose.yml.j2` — the Compose stack.
- `templates/Caddyfile.j2` — Caddy routing (incl. the Zot and OpenCode routes).

## Parameters

| Var | Default | Notes |
|---|---|---|
| `docker_dir` | `/opt/docker` | Compose project directory. |
| `arc_keyvault_name` | `homelab-bysxdb-kv` | Key Vault for all secrets. |
| `portainer_admin_password_secret_name` | `portainer-admin-password` | Portainer admin password. |
| `docker_services_caddy_bind` | `127.0.0.1:8080:8080` | Origin Caddy publish binding; `lab` sets its LAN IP so the edge Caddy can proxy to it (ADR 24 (2026-11-14 amendment)). |
| `docker_services_caddy_port` | `8080` | Host port of the bind (must match `docker_services_caddy_bind`); used for the DOCKER-USER filter. |
| `docker_services_caddy_allow_from` | `""` | Source IP allowed to reach the published origin port. Enforced in the `DOCKER-USER` chain (host UFW does not filter Docker DNAT traffic, runbook 02 §2); empty = no rule (loopback bind only). Rules persist via `iptables-persistent`. |
| `opencode_public_domain` | `example.com` | Domain for the OpenCode wildcard routes. |
| `zot_public_domain` | `example.com` | Domain for the Zot route. |
| `docker_services_networks` | `[{name: opencode_net}]` | Bridge networks to ensure. |

## Notes

- Asserts `inventory_hostname` is `lab` or `cloudlab`; applied by `playbook-lab.yml` since the cloudlab → lab migration (runbook 47); `playbook.yml` (cloudlab) no longer includes it.
- The Caddyfile site blocks listen on `:8080` (the published origin port); the edge Caddy proxies the public hostnames here with `Host` preserved. Portainer and Zot stay loopback-only, reached through this origin Caddy.
- Portainer's admin user is initialised from the Key Vault password and treats `409` (already initialised) as success.

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
