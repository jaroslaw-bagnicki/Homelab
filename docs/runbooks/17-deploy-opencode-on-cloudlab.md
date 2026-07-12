# OpenCode Server Instances on Cloudlab

> Runbook for the `docker_opencode_ingress` and `docker_opencode_instances` Ansible roles — per-project OpenCode server instances on Cloudlab via `docker_container`, with KV-backed `OPENCODE_SERVER_PASSWORD` and wildcard `*-oc.<domain>` ingress routed via a dedicated `caddy-opencode` container.

## Prerequisites

- [ ] Runbooks [1](1-init.md), [2](2-docker.md), [4](4-caddy.md), [5](5-cloudflare-tunnel.md), [10](10-vps-playground.md), [16](16-docker-services-ansible-role.md) completed
- [ ] Ansible collections installed: `community.docker`, `community.general`, `azure.azcollection` (`ansible-galaxy collection install -r ansible/requirements.yml`)
- [ ] `homelab-bysxdb-kv` Key Vault accessible from the Ansible controller identity
- [ ] SSH access to `cloudlab` via `ansible_user: labadmin` (see [ansible-vps-connect skill](../../.opencode/skills/ansible-vps-connect))
- [ ] Cloudflare Tunnel `*.<domain>` → `http://caddy:80` configured (see [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md))

## 1. Role Overview

### `docker_opencode_ingress`

| File | Purpose |
|---|---|
| `ansible/roles/docker_opencode_ingress/defaults/main.yml` | `opencode_public_domain: example.com` |
| `ansible/roles/docker_opencode_ingress/tasks/main.yml` | Assert host → ensure `/etc/opencode/ingress` → ensure `opencode_net` → template `Caddyfile.j2` + `docker-compose.yml.j2` → deploy `caddy-opencode` |
| `ansible/roles/docker_opencode_ingress/handlers/main.yml` | `Restart caddy-opencode` |
| `ansible/roles/docker_opencode_ingress/templates/Caddyfile.j2` | Per-instance `handle @inst_<name>` block for `*.<name>-oc.<domain>`, reverse-proxy to `opencode-<name>:4096` via Docker DNS on `opencode_net` |
| `ansible/roles/docker_opencode_ingress/templates/docker-compose.yml.j2` | `caddy-opencode` service on external `opencode_net`, localhost `127.0.0.1:8090:8080` for debug |

### `docker_opencode_instances`

| File | Purpose |
|---|---|
| `ansible/roles/docker_opencode_instances/defaults/main.yml` | `opencode_instances_dir: /var/lib/opencode/instances`, KV name, password secret template |
| `ansible/roles/docker_opencode_instances/tasks/main.yml` | Loop `opencode_instances` → mkdir per-instance data dirs → fetch `OPENCODE_SERVER_PASSWORD` from KV → deploy container via `docker_container` → health check via `docker_container_exec` |
| `ansible/roles/docker_opencode_instances/handlers/main.yml` | `Restart opencode instance` (looped) |

### Host vars

| File | Purpose |
|---|---|
| `ansible/host_vars/cloudlab.yml` | `opencode_public_domain: cloud5.ovh` override + `opencode_instances:` list (homelab, prospera) |

### `docker_services` integration

The existing `docker_services` role gains `opencode_public_domain` (default `example.com`, overridden to `cloud5.ovh` via host_vars) plus a new wildcard site block in `Caddyfile.j2` that proxies `*-oc.<domain>` traffic to `caddy-opencode:80`. The `oc` suffix is hardcoded in the Caddyfile template. The caddy container joins the external `opencode_net` to reach the dedicated ingress.

## 2. Services

| Service | Image | Port binding | Network | Compose |
|---|---|---|---|---|
| `caddy-opencode` | `caddy:2-alpine` | `127.0.0.1:8090:8080` (debug) | `opencode_net` (external) | `docker_opencode_ingress` role |
| `opencode-homelab` | `ghcr.io/anomalyco/opencode:latest` | none (internal only) | `opencode_net` (external) | `docker_opencode_instances` role |
| `opencode-prospera` | `ghcr.io/anomalyco/opencode:latest` | none (internal only) | `opencode_net` (external) | `docker_opencode_instances` role |

All three containers are attached only to `opencode_net`, which is created by the ingress role and bridged by `caddy` (which also lives on `homelab_net` for the management side). Reachability flows: `internet → cloudflared → caddy-main:80 → caddy-opencode:80 (Docker DNS) → opencode-<name>:4096`.

## 3. Secret handling

One secret is fetched from `homelab-bysxdb-kv` per instance via `azure.azcollection.azure_keyvault_secret` lookup (`delegate_to: localhost`, `no_log: true`):

| Secret name template | Mapped env var |
|---|---|
| `opencode-{name}-server-password` | `OPENCODE_SERVER_PASSWORD` |

Other env vars (`OPENCODE_SERVER_HOSTNAME=0.0.0.0`) are inline in the role task. API keys (OpenAI/Anthropic/Zen) are intentionally **not** passed as env vars — they live in the persistent `auth.json` that OpenCode writes under `~/.local/share/opencode/auth.json` on first login.

**No `.env` file is rendered on the host.** Secrets are fetched fresh on every playbook run; rotated passwords take effect on the next Ansible run (restart handler fires on env-vars change).

Provision secrets before the first playbook run:

```powershell
$vault = "homelab-bysxdb-kv"
Set-AzKeyVaultSecret -VaultName $vault -Name "opencode-homelab-server-password" -SecretValue (ConvertTo-SecureString -AsPlainText (New-Guid).Guid -Force) | Out-Null
Set-AzKeyVaultSecret -VaultName $vault -Name "opencode-prospera-server-password" -SecretValue (ConvertTo-SecureString -AsPlainText (New-Guid).Guid -Force) | Out-Null
```

## 4. Host on-disk layout

After a successful Stage 2 rollout:

```
/etc/opencode/ingress/
├── Caddyfile                       # templated by docker_opencode_ingress
└── docker-compose.yml              # templated by docker_opencode_ingress

/var/lib/opencode/instances/
├── homelab/
│   ├── data/                       # bind-mounted → ~/.local/share/opencode
│   ├── state/                      # bind-mounted → ~/.local/state/opencode
│   ├── config/                     # bind-mounted → ~/.config/opencode
│   └── workspace/                  # bind-mounted → /workspace
└── prospera/
    ├── data/
    ├── state/
    ├── config/
    └── workspace/
```

Per-instance directories are owned by `1000:1000` by default (matches the typical UID of the `opencode` user inside the upstream image). Verify on cloudlab with `docker run --rm ghcr.io/anomalyco/opencode:latest id` and adjust ownership if mismatched.

## 5. Role Idempotency

Both roles use `community.docker.docker_container` / `community.docker.docker_compose_v2` with `state: started` / `state: present` and `pull: true` by default. On the first run:

1. `opencode_net` bridge network is created
2. `caddy-opencode` is deployed and joined to `opencode_net`
3. `caddy` (from `docker_services`) is redeployed to pick up the new `opencode_net` network attachment
4. Each OpenCode instance is deployed via `docker_container`
5. Each instance's `/global/health` endpoint is polled until 200 (retries 12×5s)

Subsequent runs with no template, image, or KV change report `changed=0`. Password rotations trigger `Restart opencode instance` for the affected container.

## 6. Playbook Integration

The OpenCode workload is **decoupled** from the main playbook. Run two steps:

```bash
ansible-playbook ansible/playbooks/playbook.yml          # base setup
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml  # OpenCode workload
```

`opencode_net` is self-declared independently in two places:

1. `ansible/playbooks/playbook.yml` pre_tasks — ensures the network before any role runs.
2. `ansible/workloads/opencode/docker_opencode_ingress/tasks/main.yml` — `community.docker.docker_network` task.

Both declarations are idempotent. First writer wins; the second is a no-op. The network survives both playbook runs.

The OpenCode workload playbook itself has no pre_tasks. The two co-located roles (`docker_opencode_ingress`, `docker_opencode_instances`) handle their own network and KV requirements.

The runbook workflow is `bash` shell commands on a host with `ansible-playbook` installed. Inside the dev container or against cloudlab SSH, the two-step order produces an idempotent deployment: running the workload twice without changes reports `changed=0`.

## 7. Verification Checklist

- [ ] External network exists: `docker network ls` → `opencode_net`
- [ ] `caddy-opencode` is up: `docker ps --filter name=caddy-opencode` → status `Up`
- [ ] `caddy` has `opencode_net` attached: `docker inspect caddy | jq '.[0].NetworkSettings.Networks | keys'` → includes `opencode_net`
- [ ] Each instance is up: `docker ps --filter name=opencode-` → status `Up` for both `opencode-homelab` and `opencode-prospera`
- [ ] Local debug: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090` → `404` (no subdomain via localhost)
- [ ] Internal reverse proxy: `docker exec caddy-opencode wget -qO- http://opencode-homelab:4096/global/health` → `{"healthy":true,...}`
- [ ] Internal reverse proxy: `docker exec caddy-opencode wget -qO- http://opencode-prospera:4096/global/health` → `{"healthy":true,...}`
- [ ] No host Docker socket mounted: `docker inspect opencode-homelab | jq '.[0].HostConfig.Binds'` → empty array
- [ ] Per-instance dirs owned by container user: `ls -ld /var/lib/opencode/instances/*/{data,state,config,workspace}` (should be writable for the container process)
- [ ] Via Cloudflare Tunnel: `curl -u opencode:$PASSWORD https://homelab-oc.cloud5.ovh/global/health` → `{"healthy":true,...}`
- [ ] Via Cloudflare Tunnel: same check against `https://prospera-oc.cloud5.ovh/global/health`

The `cloud5.ovh` literal in this runbook reflects the cloudlab deployment. The `opencode_public_domain` Ansible var controls it; substitute accordingly when targeting a different host. The `oc` suffix is hardcoded in the Caddyfile template.

## 8. Cloudflare Tunnel DNS prerequisites

The CF tunnel wildcard entry must cover `*.<domain>` (see [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md)) and point to `http://caddy:80`. Public hostname entries in the Cloudflare Zero Trust dashboard are not required when the tunnel uses a wildcard rule. If the existing tunnel entry is the apex only, add `*.<domain>` to route agent subdomains through the same tunnel to `caddy-main`.

---

## Next Steps

- **Backup strategy** for `/var/lib/opencode/instances/<name>/` — follow-up issue (single `restic` snapshot covers all four data dirs per instance)
- **Docker AI Sandboxes (`sbx`)** evaluation once KVM availability on Cloudlab is confirmed (per [Research 21](../research/21-opencode-sandboxed-homelab-architecture.md) open question #4)
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
