# Homelab Setup — Docker Services Ansible Role

> Runbook for the `docker_services` Ansible role — deploys Portainer, Caddy, Hello World, and Cloudflare Tunnel (`cloudflared`) on Cloudlab via `community.docker.docker_compose_v2`.

## Prerequisites

- [ ] Ansible playbook running from the repo root (see [ansible/README.md](../../ansible/README.md))
- [ ] `docker_host` role completed (Docker Engine + Compose plugin installed) — see [2-docker.md](2-docker.md)
- [ ] `security` role completed (UFW configured) — see runbook §4
- [ ] `community.docker` collection installed (`ansible-galaxy collection install -r ansible/requirements.yml`)
- [ ] **Python packages for KV lookup** — the `azure.azcollection.azure_keyvault_secret` lookup requires `azure-identity` and `azure-keyvault-secrets`:
  ```bash
  sudo apt install -y python3-pip
  pip3 install --break-system-packages azure-identity azure-keyvault-secrets
  ```
- [ ] SSH access to `cloudlab` via `ansible_user: labadmin`
- [ ] **Cloudflare dashboard setup completed** — see §6 (one-time, manual)

---

## 1. Role Overview

| File | Purpose |
|---|---|
| `ansible/roles/docker_services/defaults/main.yml` | Role defaults: `docker_dir`, `arc_*` (tenant/sub/vault), `cloudflared_*_secret_name` |
| `ansible/roles/docker_services/tasks/main.yml` | Validate host → ensure `docker_dir` → fetch tunnel token from KV → write `.env` → template files → `docker compose up` |
| `ansible/roles/docker_services/handlers/main.yml` | `Restart Caddy` (on Caddyfile change), `Redeploy docker services` (on compose change) |
| `ansible/roles/docker_services/templates/docker-compose.yml.j2` | Service definitions: portainer, caddy, **cloudflared**, hello + `homelab_net` + `portainer_data` |
| `ansible/roles/docker_services/templates/Caddyfile.j2` | Per-host HTTP site blocks + `:8080` local debug endpoint |

---

## 2. Services

| Service | Image | Port binding | Network | Notes |
|---|---|---|---|---|
| Portainer | `portainer/portainer-ce:latest` | `127.0.0.1:9000:9000` | `homelab_net` | Localhost-only UI |
| Caddy | `caddy:2-alpine` | `127.0.0.1:8080:8080` | `homelab_net` | Loopback-only 8080 debug endpoint. No external port 80/443 — all public traffic arrives through the Cloudflare Tunnel |
| cloudflared | `cloudflare/cloudflared:latest` | none (outbound QUIC only) | `homelab_net` | Reads `TUNNEL_TOKEN` from `{{ docker_dir }}/.env` |
| Hello | `nginxdemos/hello:latest` | none (proxied internally) | `homelab_net` | Reverse-proxied via Caddyfile for `hello.cloud5.ovh` |

Caddy serves plain HTTP for tunnel traffic (cloudflared connects to `http://caddy:80`). Cloudflare terminates public TLS at the edge. The debug endpoint on 8080 is for local health checks without the tunnel.

---

## 3. Role Idempotency

The role uses `community.docker.docker_compose_v2` with `state: present` and `pull: always`. On first run it deploys all 4 containers. On subsequent runs:

- KV fetch tasks re-run but produce the same `register:` value (no actual change in the fetched secret)
- File-write tasks (`copy: content=...`) are no-ops if file content matches
- `docker_compose_v2` reports `changed=0` if no service-level changes

Expected second-run output: `changed=0` for all `docker_services` tasks (handlers may still run if a template file changed).

---

## 4. Playbook Integration

The `docker_services` role runs last in `ansible/playbooks/playbook.yml`. The `security` role (run before `docker_host`) must allow outbound UDP/7844 for cloudflared's QUIC connection:

```yaml
roles:
  - common
  - security
  - azure_arc
  - docker_host
  - docker_services
```

`security` role defaults that govern cloudflared connectivity (see `ansible/roles/security/defaults/main.yml`):
- `security_ufw_deny_inbound_tcp_80: true` — deny direct public HTTP (defense in depth)
- `security_cloudflared_outbound_enabled: true` — allow outbound UDP 7844
- `security_cloudflared_quic_port: 7844` — cloudflared's QUIC port to CF edge

---

## 5. Verification Checklist

- [ ] Role is idempotent: second run reports `changed=0` for the `docker_services` tasks
- [ ] All 4 containers running: `docker ps` shows `portainer`, `caddy`, `cloudflared`, `hello` all `Up`
- [ ] cloudflared connected: `docker logs cloudflared 2>&1 | grep -i 'connection.*registered'` shows a successful registration
- [ ] Local Caddy debug endpoint works: from the VPS, `curl -s http://127.0.0.1:8080` returns `Caddy debug: OK`
- [ ] HTTPS through Cloudflare Tunnel works: from any internet device, `curl -sI https://cloud5.ovh` returns `HTTP/2 200` with a valid CF edge cert
- [ ] Hello service reachable through tunnel: from any internet device, `curl -sI https://hello.cloud5.ovh` returns `HTTP/2 200` (proxied to `hello` container)
- [ ] Portainer NOT exposed publicly: `curl -s --connect-timeout 5 http://173.249.27.13:9000` → connection refused or timeout
- [ ] Direct HTTP blocked: `curl -s --connect-timeout 5 http://173.249.27.13` → connection refused (UFW deny 80)
- [ ] `.env` file permissions correct: `ls -la /opt/docker/.env` → mode `0600`

---

## 6. Cloudflare Dashboard Setup (manual, one-time)

Before the first `ansible-playbook` run, complete these steps in the [Cloudflare dashboard (cloud5.ovh)](https://dash.cloudflare.com/b7208cffa068d8f825142ea9fd426558/cloud5.ovh) and [Azure portal](https://portal.azure.com/). The role fails loudly if any KV secret is missing.

### 6.1 — Create Cloudflare Tunnel

Navigate: [**Zero Trust** → **Networks** → **Tunnels**](https://dash.cloudflare.com/b7208cffa068d8f825142ea9fd426558/tunnels/9558d789-1623-4b9e-ac67-3a1170ec9c0b/overview) → **Create a tunnel**

- Connector type: **Cloudflared**
- Name: `cloudlab-tunnel` (any name works — the role's defaults derive Key Vault secret names from `inventory_hostname` via the `cloudflared_*_secret_name` vars)

Click **Save tunnel**. **Copy the tunnel token** (shown once) — store in a temp file.



In the CF dashboard, [**Zero Trust** → **Networks** → **Tunnels** → `cloudlab-tunnel` → **Connectors** tab](https://dash.cloudflare.com/b7208cffa068d8f825142ea9fd426558/tunnels/9558d789-1623-4b9e-ac67-3a1170ec9c0b/overview). After the first `ansible-playbook` run, the **Connectors** tab should show `cloudlab` with status **Active**. If **Inactive** or **Down**, debug via `docker logs cloudflared` on the VPS.

### 6.2 — Cloudflare Access policy for admin services (recommended)

Admin-facing services (Portainer, anything with full-host control) sit behind the same tunnel+Caddy path but should be wrapped with a **Cloudflare Access** policy at the edge. This adds identity-verified single-use JWT enforcement *before* traffic reaches the backend — the browser never speaks directly to Portainer until the user passes the Access gate.

**Scope the policy per-hostname** so the rule only applies to the public surface you want to gate. The dashboard walks you through:

- **Zero Trust → Access → Applications** → **Add an application** → **Self-hosted**
- Application name: e.g. `portainer` (display only)
- **Application domain**: `portainer.cloud5.ovh` (matches the public hostname exactly — subdomain scoping, no wildcard)
- **Session duration**: short (e.g. 24 hours) and **Apply HTTP-only, Secure** cookie attributes
- **Identity providers**: link the IdP you want — email one-time PIN works fine for a single-user lab; add OIDC / Google / GitHub later if multi-user
- **Policy**: at minimum an **Allow** rule keyed to your email/identity; for stricter posture add **Require country** or **IP range**
- **Block / Allow ordering**: leave Access's defaults; the implicit deny covers anything not matched

After saving, a hit on `https://portainer.cloud5.ovh/` from an unauthenticated browser returns a 302 to `https://<team>.cloudflareaccess.com/...` for IdP login. With a valid session, traffic flows through to Caddy → Portainer as normal.

**Why this matters**: the tunnel → Caddy hop carries plaintext HTTP internally (per [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md)). Cloudflare Access closes the trust gap at the edge without touching the in-cluster network — no Caddy mTLS, no per-service auth glue, no application code changes.

---

## Adding New Services

To expose a new service (e.g. `portainer.cloud5.ovh`) through the tunnel:

1. **Caddyfile.j2**: add a new HTTP site block:
   ```Caddyfile
   http://portainer.cloud5.ovh {
       reverse_proxy portainer:9000
   }
   ```
2. **CF dashboard** (if not using wildcard): add a new public hostname on the tunnel
3. **Cloudflare Access**: if the service is admin-facing, add an Access policy scoped to the new hostname (see §6.2 above)
4. **Run the playbook** — idempotent re-deploy

---

## Next Steps

- Migrate KV secret fetching from the dev container (SP + env vars) to the VPS using the Arc system-assigned Managed Identity — file as a follow-up issue
- Issue #23 (DNS A record for `cloudlab.cloud5.ovh` in OVH DNS) — separate from this work; keep open for SSH / non-tunnel access
- Issue #24 (Let's Encrypt TLS) — **superseded by this work**, close in housekeeping commit

---

## Related

- [Research 18 — Docker-Compose Replication](../research/18-docker-compose-replication.md)
- [ADR 07 — Reverse Proxy: Caddy](../decisions/07-reverse-proxy-caddy.md)
- [ADR 08 — Remote Access: Cloudflare Tunnel](../decisions/08-remote-access-cloudflare-tunnel.md)
- [ADR 10 — Ansible for Host Configuration Management](../decisions/10-ansible-host-config.md)
- [ADR 19 — Cloudflare Tunnel HTTP origin with Caddy reverse proxy on Cloudlab](../decisions/19-cloudflare-tunnel-https-origin.md)
