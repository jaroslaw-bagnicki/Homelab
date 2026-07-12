# OpenCode Server Instances on Cloudlab

> Runbook for the `docker_opencode_ingress` and `docker_opencode_instance` Ansible roles — deploys per-project OpenCode server instances (default: `opencode-homelab`, `opencode-prospera`) on Cloudlab via `community.docker.docker_compose_v2`, with KV-backed `OPENCODE_SERVER_PASSWORD` and wildcard `*-oc.cloud5.ovh` ingress.

## Prerequisites

- [ ] Runbooks [1](1-init.md), [2](2-docker.md), [4](4-caddy.md), [5](5-cloudflare-tunnel.md), [10](10-vps-playground.md), [16](16-docker-services-ansible-role.md) completed
- [ ] Ansible playbook running from the repo root (see [ansible/README.md](../../ansible/README.md))
- [ ] `community.docker` collection installed (`ansible-galaxy collection install -r ansible/requirements.yml`)
- [ ] `azure.azcollection` collection installed for Key Vault secret fetch
- [ ] `homelab-bysxdb-kv` Key Vault accessible from the Ansible controller identity
- [ ] SSH access to `cloudlab` via `ansible_user: labadmin`
- [ ] Cloudflare Tunnel `*.cloud5.ovh → http://caddy:80` configured (see [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md))

## 1. Role Overview

### `docker_opencode_ingress`

| File | Purpose |
|---|---|
| `ansible/roles/docker_opencode_ingress/defaults/main.yml` | `opencode_ingress_dir`, `opencode_network_name: opencode_net`, ingress image, root domain |
| `ansible/roles/docker_opencode_ingress/tasks/main.yml` | Create directory → ensure `opencode_net` bridge network → template `Caddyfile.j2` + `docker-compose.yml.j2` → deploy `caddy-opencode` |
| `ansible/roles/docker_opencode_ingress/handlers/main.yml` | `Restart caddy-opencode`, `Redeploy opencode ingress` |
| `ansible/roles/docker_opencode_ingress/templates/Caddyfile.j2` | Wildcard `*.<prefix>.<root_domain>` reverse-proxy to `opencode-{labels.2}:4096` via Docker DNS on `opencode_net` |
| `ansible/roles/docker_opencode_ingress/templates/docker-compose.yml.j2` | `caddy-opencode` service on `opencode_net` (external), localhost `127.0.0.1:8090:8080` for debug |

### `docker_opencode_instance`

| File | Purpose |
|---|---|
| `ansible/roles/docker_opencode_instance/defaults/main.yml` | `opencode_instances_root`, KV name, secret-name templates, `opencode_api_key_env_vars` |
| `ansible/roles/docker_opencode_instance/tasks/main.yml` | Loop `opencode_instances` → fetch `OPENCODE_SERVER_PASSWORD` from KV → write `.env` → `docker compose up` → health-check `/global/health` |
| `ansible/roles/docker_opencode_instance/handlers/main.yml` | `Restart opencode instance`, `Redeploy opencode instances` |
| `ansible/roles/docker_opencode_instance/templates/env.j2` | Per-instance `.env` rendering password + optional API keys from host-side facts |

### Host vars

| File | Purpose |
|---|---|
| `ansible/host_vars/cloudlab.yml` | `opencode_instances:` list — names, compose-file paths, image, port, workspace ownership |

### Docker assets (in repo, copied to host at role runtime)

| File | Purpose |
|---|---|
| `docker/opencode-server/Dockerfile` | Common image extending `ghcr.io/anomalyco/opencode` with ansible + bicep + jq + git + ssh-client |
| `docker/opencode-homelab/docker-compose.yml` | `opencode-homelab` instance: shared tooling + workspace bind-mount `/var/lib/opencode/workspaces/homelab` |
| `docker/opencode-prospera/docker-compose.yml` | `opencode-prospera` instance: shared tooling + workspace bind-mount `/var/lib/opencode/workspaces/prospera` |

### `caddy-main` integration (existing role)

| File | Purpose |
|---|---|
| `ansible/roles/docker_services/templates/Caddyfile.j2` | Adds `http://*.oc.cloud5.ovh` block that reverse-proxies to `caddy-opencode:80` |
| `ansible/roles/docker_services/templates/docker-compose.yml.j2` | Adds `caddy` to the external `opencode_net` network so `caddy-main` can reach `caddy-opencode` |

## 2. Services

| Service | Image | Port binding | Network |
|---|---|---|---|
| `caddy-opencode` | `caddy:2-alpine` | `127.0.0.1:8090:8080` | `opencode_net` (external) |
| `opencode-homelab` | `opencode-server:latest` (built on host from `docker/opencode-server/Dockerfile`) | none (exposed to `opencode_net` only) | `opencode_net` (external) |
| `opencode-prospera` | `opencode-server:latest` (built on host from `docker/opencode-server/Dockerfile`) | none (exposed to `opencode_net` only) | `opencode_net` (external) |

The `opencode-server:latest` image is rebuilt on the host on every `docker_compose_v2` invocation that changes the image build context. Each instance stores its data in three named volumes (`data`, `state`, `config`) and bind-mounts `/var/lib/opencode/workspaces/<name>` for project checkout.

## 3. Secret handling

Two secrets are fetched from `homelab-bysxdb-kv` per instance via `azure.azcollection.azure_keyvault_secret` (lookup runs `delegate_to: localhost` with `no_log: true`):

| Secret name template | Mapped env var | Default contents |
|---|---|---|
| `opencode-{name}-server-password` | `OPENCODE_SERVER_PASSWORD` | one-of `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` (HTTP basic auth) |
| `opencode-{name}-api-key` (optional, one per env var listed in `host_vars.opencode_instances[].api_key_env_vars`) | `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENCODE_ZEN_API_KEY` | optional — only written if the secret exists |

A secret value that is missing for a listed API key is silently skipped (the resulting `.env` line is empty). Operators should pre-provision secrets before the first playbook run:

```powershell
$vault = "homelab-bysxdb-kv"
Set-AzKeyVaultSecret -VaultName $vault -Name "opencode-homelab-server-password" -SecretValue (ConvertTo-SecureString -AsPlainText (New-Guid).Guid -Force) | Out-Null
Set-AzKeyVaultSecret -VaultName $vault -Name "opencode-prospera-server-password" -SecretValue (ConvertTo-SecureString -AsPlainText (New-Guid).Guid -Force) | Out-Null
```

The `.env` file is rendered with `mode: "0600"` and never logged.

## 4. Role Idempotency

The roles use `community.docker.docker_compose_v2` with `state: present` and `pull: true` by default. On the first run the roles:

1. Create the `opencode_net` bridge network
2. Deploy `caddy-opencode` from the Caddy image (pulled)
3. Build `opencode-server:latest` from `docker/opencode-server/Dockerfile`
4. Deploy each instance, run `/global/health` until 200 or 401 (basic-auth challenge)

Subsequent runs with no template, image, or secret change report `changed=0`. Caddy reloads restart only the `caddy-opencode` container; image rebuilds redeploy the affected instance.

## 5. Playbook Integration

`docker_opencode_ingress` and `docker_opencode_instance` append to `ansible/playbooks/playbook.yml` after `docker_services`:

```yaml
roles:
  - common
  - security
  - azure_arc
  - docker_host
  - docker_services
  - docker_opencode_ingress
  - docker_opencode_instance
```

Both roles are guarded by `inventory_hostname in ['homelab', 'cloudlab']` (mirroring `docker_services`).

## 6. Verification Checklist

- [ ] External network exists: `docker network ls` → `opencode_net`
- [ ] `caddy-opencode` is up: `docker ps --filter name=caddy-opencode` → status `Up`
- [ ] Each instance is up: `docker ps --filter name=opencode-` → status `Up` for both `opencode-homelab` and `opencode-prospera`
- [ ] Local debug endpoint: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090` → `404` (no subdomain via localhost) or `200` when hostname header matches a known instance
- [ ] Internal reverse proxy: from inside `caddy-opencode`, `docker exec caddy-opencode wget -qO- http://opencode-homelab:4096/global/health` → `{"healthy":true,...}`
- [ ] Per-instance `.env` exists with `mode 0600`: `ls -l /etc/opencode/instances/homelab/.env`
- [ ] No host Docker socket mounted: `docker inspect opencode-homelab | jq '.[0].HostConfig.Binds'` → empty array
- [ ] Via Cloudflare Tunnel: `curl -u opencode:$PASSWORD https://homelab-oc.cloud5.ovh/global/health` → `{"healthy":true,...}` (after DNS + public hostname entry in CF Zero Trust dashboard)
- [ ] Via Cloudflare Tunnel: same check against `https://prospera-oc.cloud5.ovh/global/health`

## 7. Cloudflare Tunnel DNS prerequisites

The CF tunnel wildcard entry must cover `*.cloud5.ovh` (see [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md)) and point to `http://caddy:80`. Public hostname entries in the Cloudflare Zero Trust dashboard are not required when the tunnel uses a wildcard rule. If the existing tunnel entry is the apex only, add `*.cloud5.ovh` to route agent subdomains through the same tunnel to `caddy-main`.

## Next Steps

- **Backup strategy** for OpenCode named volumes and workspace directories (follow-up issue)
- **Docker AI Sandboxes (`sbx`)** evaluation once KVM availability on Cloudlab is confirmed (per Research 21 open question #4)
- Add Cloudflare Access or Caddy basic-auth layered on top of OpenCode's built-in auth if multi-user access becomes a requirement

---

## Related

- [ADR 18 — Host OpenCode Server Instances on Cloudlab](../decisions/18-opencode-docker-sandbox.md)
- [ADR 19 — Cloudflare Tunnel HTTP origin with Caddy reverse proxy](../decisions/19-cloudflare-tunnel-https-origin.md)
- [ADR 20 — Caddy as Single Routing Layer on Cloudlab](../decisions/20-caddy-single-routing-layer.md)
- [Research 21 — OpenCode Sandboxed Architecture on Homelab](../research/21-opencode-sandboxed-homelab-architecture.md)
- [Research 22 — Infisical vs Azure Key Vault](../research/22-infisical-vs-azure-key-vault.md)
- [Runbook 16 — Docker Services Ansible Role](16-docker-services-ansible-role.md)
- [#30 — Implement server-hosted OpenCode instances on Cloudlab](https://github.com/jaroslaw-bagnicki/Homelab/issues/30)
