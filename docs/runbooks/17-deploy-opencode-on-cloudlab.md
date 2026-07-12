# OpenCode Server Instances on Cloudlab

> Runbook for the `ansible/workloads/opencode/` workload — per-project OpenCode server instances on Cloudlab. Workload description, capabilities, services, host layout, secret handling, and idempotency live in [the workload README](../../ansible/workloads/opencode/README.md). This runbook covers the operational steps: prerequisites, deploy invocation, and verification.

## Prerequisites

- [ ] Runbooks [1](1-init.md), [2](2-docker.md), [4](4-caddy.md), [5](5-cloudflare-tunnel.md), [10](10-vps-playground.md), [16](16-docker-services-ansible-role.md) completed.
- [ ] Ansible collections installed: `community.docker`, `community.general`, `azure.azcollection` (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] `homelab-bysxdb-kv` Key Vault accessible from the Ansible controller identity, with secrets for each instance (see workload README §Secret handling).
- [ ] SSH access to `cloudlab` via `ansible_user: labadmin` (see [ansible-vps-connect skill](../../.opencode/skills/ansible-vps-connect)).
- [ ] Cloudflare Tunnel `*.<domain>` → `http://caddy:80` configured (see [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md)).

## 1. Deploy

The OpenCode workload is **decoupled** from the main playbook. Run two steps:

```bash
ansible-playbook ansible/playbooks/playbook.yml                    # base setup
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml  # OpenCode workload
```

`opencode_net` is self-declared independently in two places:

1. `ansible/playbooks/playbook.yml` pre_tasks — ensures the network before any role runs.
2. `ansible/workloads/opencode/docker_opencode_ingress/tasks/main.yml` — `community.docker.docker_network` task.

Both declarations are idempotent. First writer wins; the second is a no-op. The network survives both playbook runs.

The OpenCode workload playbook itself has no pre_tasks. The two co-located roles (`docker_opencode_ingress`, `docker_opencode_instances`) handle their own network and KV requirements.

The deploy workflow is `bash` shell commands on a host with `ansible-playbook` installed. Inside the dev container or against cloudlab SSH, the two-step order produces an idempotent deployment: running the workload twice without changes reports `changed=0`.

## 2. Verification Checklist

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

## 3. Cloudflare Tunnel DNS prerequisites

The CF tunnel wildcard entry must cover `*.<domain>` (see [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md)) and point to `http://caddy:80`. Public hostname entries in the Cloudflare Zero Trust dashboard are not required when the tunnel uses a wildcard rule. If the existing tunnel entry is the apex only, add `*.<domain>` to route agent subdomains through the same tunnel to `caddy-main`.

---

## Next Steps

- **Backup strategy** for `/var/lib/opencode/instances/<name>/` — follow-up issue (single `restic` snapshot covers all four data dirs per instance)
- **Docker AI Sandboxes (`sbx`)** evaluation once KVM availability on Cloudlab is confirmed (per [Research 21](../research/21-opencode-sandboxed-homelab.md) open question #4)
- Add Cloudflare Access or Caddy basic-auth layered on top of OpenCode's built-in auth if multi-user access becomes a requirement

---

## Related

- [Workload README — OpenCode](../../ansible/workloads/opencode/README.md)
- [ADR 18 — Host OpenCode Server Instances on Cloudlab](../decisions/18-opencode-docker-sandbox.md)
- [ADR 19 — Cloudflare Tunnel HTTP origin with Caddy reverse proxy](../decisions/19-cloudflare-tunnel-https-origin.md)
- [ADR 20 — Caddy as Single Routing Layer on Cloudlab](../decisions/20-caddy-single-routing-layer.md)
- [Research 21 — OpenCode Sandboxed Architecture on Homelab](../research/21-opencode-sandboxed-homelab.md)
- [Research 22 — Infisical vs Azure Key Vault](../research/22-infisical-vs-azure-key-vault.md)
- [Runbook 16 — Docker Services Ansible Role](16-docker-services-ansible-role.md)
- [#30 — Implement server-hosted OpenCode instances on Cloudlab](https://github.com/jaroslaw-bagnicki/Homelab/issues/30)
