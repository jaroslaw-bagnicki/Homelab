# Zot Container Registry on Cloudlab

> Runbook for the `ansible/workloads/zot/` workload — self-hosted OCI registry on cloudlab per [issue #50](https://github.com/jaroslaw-bagnicki/Homelab/issues/50). Workload description, capabilities, services, host layout, secret handling, and idempotency live in [the workload README](../../ansible/workloads/zot/README.md). This runbook covers the operational steps: prerequisites, secret provisioning, deploy invocation, Cloudflare Tunnel routing, and verification.

> **Note:** `example.com` is a placeholder domain used throughout this runbook for documentation purposes only — it is **not** the deployed domain. The actual registry hostname is `zot.<domain>`, where `<domain>` is the Ansible `zot_public_domain` var.

## Prerequisites

- [ ] Runbooks [10](10-vps-playground.md), [16](16-docker-services-ansible-role.md) completed — cloudlab has Docker, the base Compose stack (Caddy, cloudflared), and `homelab_net`.
- [ ] Ansible collections installed: `community.docker`, `community.general`, `azure.azcollection` (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] `homelab-bysxdb-kv` Key Vault accessible from the Ansible controller identity.
- [ ] SSH access to `cloudlab` via `ansible_user: fleetadm` (see [fleet-connect skill](../../.opencode/skills/fleet-connect)).
- [ ] Cloudflare Tunnel routing to `http://caddy:80` configured (see [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md)).

## 1. Provision secrets

Before the first playbook run, provision the registry credentials in Key Vault via the provisioning script:

```powershell
.\scripts\New-HomelabZotRegistryCredential.ps1
```

The script provisions both secrets in `homelab-bysxdb-kv`:
- `zot-registry-user` — the registry username (default `zot-admin`, the `-UserName` parameter), the registry's global admin (granted via `adminPolicy`)
- `zot-registry-password` — a strong random password

The role fetches both at runtime. Retrieve the password when you need to log in:

```powershell
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name zot-registry-password -AsPlainText
```

**Rotation**: re-run `New-HomelabZotRegistryCredential.ps1 -Force` (writes a new password), then re-run the playbook — the role updates the bcrypt htpasswd file and restarts zot.

> The registry is internet-exposed, so **push and pull both require this credential**. `docker login zot.example.com` is mandatory before any push/pull.

## 2. Deploy

The Zot workload is **decoupled** from the main playbook. Run two steps:

```bash
ansible-playbook ansible/playbooks/playbook.yml                    # base setup (Caddy, tunnel, homelab_net)
ansible-playbook ansible/workloads/zot/zot-playbook.yml            # Zot workload
```

`homelab_net` is self-declared in two places — the base playbook pre_tasks and the `zot_registry` role — both idempotent, first writer wins.

The `zot.example.com` route lives in the base `docker_services` Caddyfile template (the `# BEGIN/END ZOT ROUTE` block) and is applied whenever the base playbook runs, which also restarts Caddy. This is exposure Option A; the three options (Caddy reverse proxy, zot native HTTPS on host 443, direct Cloudflare Tunnel) are documented in the [workload README — External access](../../ansible/workloads/zot/README.md).

The deploy workflow is idempotent: running the workload twice without changes reports `changed=0`.

## 3. Cloudflare Tunnel routing

With a token-based (remotely-managed) tunnel, public hostnames are routed in the Cloudflare Zero Trust dashboard:

1. Open [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → **Networks** → **Tunnels** → the cloudlab tunnel.
2. **Public Hostname** → **Add a public hostname**:
   - **Subdomain**: `zot` · **Domain**: `example.com`
   - **Service**: `HTTP` → `caddy:80`
3. Save.

Traffic flow: client → Cloudflare edge (TLS) → cloudflared → `http://caddy:80` → Caddy routes `zot.example.com` → `zot:5000`. This matches ADR 19's pattern — TLS terminates at the CF edge; origin traffic is plain HTTP on `homelab_net`.

## 4. Verification Checklist

- [ ] Zot is up: `docker ps --filter name=zot` → status `Up`
- [ ] Internal API (unauthenticated — auth is required): `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5000/v2/` → `401`
- [ ] Public catalog (over CF Tunnel): `curl -u zot-admin:$PASSWORD https://zot.example.com/v2/_catalog` → `{"repositories":[]}`
- [ ] Push round-trip: `docker login zot.example.com` → `docker tag hello-world zot.example.com/hello:test` → `docker push zot.example.com/hello:test` → `docker pull zot.example.com/hello:test`
- [ ] Pull-through cache: `docker pull zot.example.com/ghcr/project-zot/zot:v2.1.18` and `docker pull zot.example.com/dockerhub/library/alpine:latest` (first pull fetches from `ghcr.io` / Docker Hub and caches locally; a second pull is served from cache — verify the container pulls fast)
- [ ] CVE scan / web UI: `https://zot.example.com` → login with the htpasswd credential → image list renders, scan results visible
- [ ] Idempotency: re-run `ansible-playbook ansible/workloads/zot/zot-playbook.yml` → `changed=0`

> Pull-through cache prefixes: `/ghcr/...` (GHCR), `/mcr/...` (Microsoft Container Registry), `/dockerhub/...` (Docker Hub). Pull e.g. `zot.example.com/dockerhub/library/alpine:latest` for a Docker Hub image.

## Security notes

- **Auth on everything** — the registry requires the htpasswd credential for push and pull; there is no anonymous access, so the pull-through cache cannot be abused as an open proxy.
- The `search`/`ui`/`mgmt` extensions are explicitly enabled in `config.json`. The `mgmt` extension ships with a built-in `zot-admin`/`zot-admin` admin identity for its management API — acceptable for a personal homelab, but the registry is otherwise fully authenticated. Review before widening access.
- Data lives on the NVMe at `/var/lib/zot`; cloudlab is disposable (ADR 13), so no restic coverage is planned for the registry there.

---

## Next Steps

- Point the future k3s cluster (ADR 22) at the registry via containerd mirrors (`/etc/rancher/k3s/registries.yaml`) so the cluster pulls through `zot.example.com`.
- Route the cloudlab OpenCode instances' base-image pulls through the Zot cache.
- Port the workload to the physical homelab box after cloudlab validation (ADR 13 pattern).
- Entra ID SSO follow-up: dex bridge (interactive SSO) vs OIDC bearer (K8s/CI workload identity, ADR 16 alignment).

---

## Related

- [Workload README — Zot](../../ansible/workloads/zot/README.md)
- [ADR 13 — Cloudlab staging](../decisions/13-cloudlab-staging.md)
- [ADR 19 — Cloudflare Tunnel HTTP origin with Caddy reverse proxy](../decisions/19-cloudflare-tunnel-https-origin.md)
- [ADR 20 — Caddy as Single Routing Layer on Cloudlab](../decisions/20-caddy-single-routing-layer.md)
- [Runbook 16 — Docker Services Ansible Role](16-docker-services-ansible-role.md)
- [Issue #50 — Adopt Zot as self-hosted container registry](https://github.com/jaroslaw-bagnicki/Homelab/issues/50)
