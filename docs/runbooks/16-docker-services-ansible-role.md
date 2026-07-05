# Homelab Setup — Docker Services Ansible Role

> Runbook for the `docker_services` Ansible role — deploys Portainer, Caddy, Hello World, and Cloudflare Tunnel (`cloudflared`) on Cloudlab via `community.docker.docker_compose_v2`.

## Prerequisites

- [ ] Ansible playbook running from the repo root (see [ansible/README.md](../../ansible/README.md))
- [ ] `docker_host` role completed (Docker Engine + Compose plugin installed) — see [2-docker.md](2-docker.md)
- [ ] `security` role completed (UFW configured) — see runbook §4
- [ ] `community.docker` collection installed (`ansible-galaxy collection install -r ansible/requirements.yml`)
- [ ] SSH access to `cloudlab` via `ansible_user: labadmin`
- [ ] **Cloudflare dashboard setup completed** — see §6 (one-time, manual)

---

## 1. Role Overview

| File | Purpose |
|---|---|
| `ansible/roles/docker_services/defaults/main.yml` | Role defaults: `docker_dir`, `arc_*` (tenant/sub/vault), `cloudflared_*_secret_name` |
| `ansible/roles/docker_services/tasks/main.yml` | Validate host → ensure `docker_dir` → fetch 3 KV secrets → write `.env`/certs/Caddyfile → `docker compose up` |
| `ansible/roles/docker_services/handlers/main.yml` | `Restart Caddy` (on Caddyfile change), `Redeploy docker services` (on compose change) |
| `ansible/roles/docker_services/templates/docker-compose.yml.j2` | Service definitions: portainer, caddy, **cloudflared**, hello + `homelab_net` + `portainer_data` |
| `ansible/roles/docker_services/templates/Caddyfile.j2` | Per-host HTTPS site blocks + `:8080` local debug endpoint |

---

## 2. Services

| Service | Image | Port binding | Network | Notes |
|---|---|---|---|---|
| Portainer | `portainer/portainer-ce:latest` | `127.0.0.1:9000:9000` | `homelab_net` | Localhost-only UI |
| Caddy | `caddy:2-alpine` | `127.0.0.1:443:443`, `127.0.0.1:443:443/udp`, `127.0.0.1:8080:8080` | `homelab_net` | Loopback-only HTTPS + debug endpoint; reads Origin cert from `{{ docker_dir }}/certs/` bind mount |
| cloudflared | `cloudflare/cloudflared:latest` | none (outbound QUIC only) | `homelab_net` | Reads `TUNNEL_TOKEN` from `{{ docker_dir }}/.env` bind mount |
| Hello | `nginxdemos/hello:latest` | none (proxied internally) | `homelab_net` | Reverse-proxied via Caddyfile for `hello.ctb.cloud5.ovh` |

Caddy serves HTTPS only (no port 80 listener). cloudflared makes a single outbound QUIC connection to Cloudflare edge. Public HTTPS terminates at CF edge; clients see CF's public cert.

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
- [ ] HTTPS through Cloudflare Tunnel works: from any internet device, `curl -sI https://ctb.cloud5.ovh` returns `HTTP/2 200` with a valid CF edge cert
- [ ] Hello service reachable through tunnel: from any internet device, `curl -sI https://hello.ctb.cloud5.ovh` returns `HTTP/2 200` (proxied to `hello` container)
- [ ] Portainer NOT exposed publicly: `curl -s --connect-timeout 5 http://173.249.27.13:9000` → connection refused or timeout
- [ ] Direct HTTP blocked: `curl -s --connect-timeout 5 http://173.249.27.13` → connection refused (UFW deny 80)
- [ ] File permissions correct on the VPS:
  - `ls -la /opt/docker/.env` → mode `0600`
  - `ls -la /opt/docker/certs/origin.pem` → mode `0644`
  - `ls -la /opt/docker/certs/origin.key` → mode `0600`

---

## 6. Cloudflare Dashboard Setup (manual, one-time)

Before the first `ansible-playbook` run, complete these steps in the [Cloudflare dashboard](https://dash.cloudflare.com/) and [Azure portal](https://portal.azure.com/). The role fails loudly if any KV secret is missing.

### 6.1 — Create Cloudflare Tunnel

Navigate: **Zero Trust** → **Networks** → **Tunnels** → **Create a tunnel**

- Connector type: **Cloudflared**
- Name: `cloudlab-tunnel` (any name works — the role's defaults derive Key Vault secret names from `inventory_hostname` via the `cloudflared_*_secret_name` vars)

Click **Save tunnel**. **Copy the tunnel token** (shown once) — store in a temp file.

### 6.2 — Create CF Origin Certificate

Navigate: **SSL/TLS** → **Origin Server** → **Create Certificate**

- Private key type: **RSA**
- Hostnames (add both): `*.ctb.cloud5.ovh` AND `ctb.cloud5.ovh`
- Validity: **15 years**

Click **Create**. **Copy the certificate (PEM) and private key** (each shown once) — store in temp files.

### 6.3 — Configure public hostnames on the tunnel

Skip the "install connector" wizard. In the tunnel detail page → **Public Hostnames** tab → **Add a public hostname** for each service you want to expose:

- Subdomain: the service name (e.g. `hello`) or empty for the apex
- Domain: `ctb.cloud5.ovh`
- Service: **HTTPS**
- URL: `https://caddy:443`

Repeat for each service. The CF dashboard auto-creates the corresponding DNS CNAME record.

> **Note:** Cloudflare free tier does not support multi-level wildcards (`*.ctb.cloud5.ovh`). Each new service requires its own public hostname entry.

### 6.4 — Store 3 secrets in Azure Key Vault

Open a PowerShell session in the dev container (Az context auto-loads via `.devcontainer/config/profile.ps1`):

```powershell
Set-AzKeyVaultSecret -VaultName homelab-bysxdb-kv `
  -Name cloudflared-tunnel-token-cloudlab `
  -SecretValue ((Get-Content -Raw /tmp/cloudflared-tunnel-token.txt) | ConvertTo-SecureString -AsPlainText -Force)

Set-AzKeyVaultSecret -VaultName homelab-bysxdb-kv `
  -Name cloudflared-origin-cert-cloudlab `
  -SecretValue ((Get-Content -Raw /tmp/cloudflared-origin-cert-cloudlab.pem) | ConvertTo-SecureString -AsPlainText -Force)

Set-AzKeyVaultSecret -VaultName homelab-bysxdb-kv `
  -Name cloudflared-origin-key-cloudlab `
  -SecretValue ((Get-Content -Raw /tmp/cloudflared-origin-key-cloudlab.key) | ConvertTo-SecureString -AsPlainText -Force)

Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudflared-tunnel-token-cloudlab -AsPlainText | Out-Null
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudflared-origin-cert-cloudlab -AsPlainText | Out-Null
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudflared-origin-key-cloudlab -AsPlainText | Out-Null
Write-Host "All 3 secrets present in KV."
```

Sanitize the temp files: `shred -u /tmp/cloudflared-tunnel-token.txt /tmp/cloudflared-origin-cert-cloudlab.pem /tmp/cloudflared-origin-key-cloudlab.key`.

### 6.5 — Set CF SSL/TLS encryption mode

Navigate: **SSL/TLS** → **Overview** → **Encryption mode: Full (Strict)**.

Required for CF edge to validate the Origin CA cert you provisioned in §6.2.

### 6.6 — Enable "Always Use HTTPS" at CF edge

Navigate: **SSL/TLS** → **Edge Certificates** → toggle **Always Use HTTPS** to **ON**.

Public HTTP requests get 301-redirected to HTTPS at CF edge before entering the tunnel.

### 6.7 — Verify the tunnel

In the CF dashboard, **Zero Trust** → **Networks** → **Tunnels** → `cloudlab-tunnel` → **Connectors** tab. After the first `ansible-playbook` run, the **Connectors** tab should show `cloudlab` with status **Active**. If **Inactive** or **Down**, debug via `docker logs cloudflared` on the VPS.

---

## Adding New Services

To expose a new service (e.g. `portainer.ctb.cloud5.ovh`) through the tunnel:

1. **CF dashboard**: add a new public hostname on the tunnel (`portainer.ctb.cloud5.ovh` → `https://caddy:443`)
2. **CF dashboard**: regenerate the Origin cert with the new SAN, store new PEM in KV (overwrite `cloudflared-origin-cert-cloudlab`)
3. **Caddyfile.j2**: add a new site block:
   ```
   https://portainer.ctb.cloud5.ovh {
       tls /etc/caddy/certs/origin.pem /etc/caddy/certs/origin.key
       reverse_proxy portainer:9000
   }
   ```
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
- [ADR 19 — HTTPS-only origin via Cloudflare Tunnel + Cloudflare Origin CA on Cloudlab](../decisions/19-cloudflare-tunnel-https-origin.md)
