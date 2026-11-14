# cloudflared

Installs `cloudflared` as a **bare-metal systemd service** on the `edge` appliance — the public Cloudflare Tunnel ingress (ADR 53, deployment model per ADR 24: no Docker on the edge box). The tunnel token comes from Key Vault at run time.

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — assert host → download `.deb` → install → config dir → KV token → `.env` (0600, no_log) → unit → enable/start.
- `templates/cloudflared.service.j2` — systemd unit, `After=caddy.service`, `EnvironmentFile=/etc/cloudflared/.env`.
- `handlers/main.yml` — restart cloudflared.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `cloudflared_deb_url` | cloudflare `latest` linux-amd64 `.deb` | Install source. |
| `cloudflared_config_dir` | `/etc/cloudflared` | Holds the `.env`. |
| `arc_keyvault_name` | `homelab-bysxdb-kv` | Key Vault for the token. |
| `cloudflared_token_secret_name` | `cloudflared-tunnel-token-<host>` | Per-host tunnel token secret. |
| `cloudflared_origin` | `http://127.0.0.1:80` | Documented origin: the edge Caddy on loopback (TLS terminates at the CF edge, ADR 19). |

## Notes

- Asserts `inventory_hostname == 'edge'` — the public tunnel lives on the edge appliance only (ADR 53).
- The `.env` is written `0600`, `no_log`. Public hostnames and their service targets are configured in the Cloudflare Zero Trust dashboard, not in this role.
- The same tunnel token is reused across the cloudlab → edge move (runbook 47), so the `cloud5.ovh` CNAME needs no DNS change; only the connector host changes.

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
