# docker_services

Deploys the core Docker Compose stack on `cloudlab` — Portainer, Caddy (reverse proxy, auto-TLS), and cloudflared (Cloudflare Tunnel) — plus the shared bridge networks. Secrets are read from Key Vault at run time.

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — networks, secrets, templates, Compose up, Portainer bootstrap.
- `handlers/main.yml` — restart Caddy, restart cloudflared, redeploy the stack.
- `templates/docker-compose.yml.j2` — the Compose stack.
- `templates/Caddyfile.j2` — Caddy routing (incl. the Zot and OpenCode routes).

## Parameters

| Var | Default | Notes |
|---|---|---|
| `docker_dir` | `/opt/docker` | Compose project directory. |
| `arc_keyvault_name` | `homelab-bysxdb-kv` | Key Vault for all secrets. |
| `cloudflared_token_secret_name` | `cloudflared-tunnel-token-<host>` | Tunnel token, per host. |
| `portainer_admin_password_secret_name` | `portainer-admin-password` | Portainer admin password. |
| `opencode_public_domain` | `example.com` | Domain for the OpenCode wildcard routes. |
| `zot_public_domain` | `example.com` | Domain for the Zot route. |
| `docker_services_networks` | `[{name: opencode_net}]` | Bridge networks to ensure. |

## Notes

- Asserts `inventory_hostname` is `lab` or `cloudlab`; in practice only `playbook.yml` (cloudlab) applies it — `playbook-lab.yml` omits it ([ADR 24](../../../docs/decisions/24-edge-ingress-appliance.md)).
- The cloudflared `.env` (tunnel token) is written `0600`, `no_log`, and listed in a `.gitignore`.
- Portainer's admin user is initialised from the Key Vault password and treats `409` (already initialised) as success.

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
