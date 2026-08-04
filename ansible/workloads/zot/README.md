# Zot workload

## Purpose

A self-contained Ansible recipe that deploys the **Zot OCI container registry** (`ghcr.io/project-zot/zot`) on cloudlab, exposing a public registry at `zot.<domain>` and caching upstream pulls. Per issue #50, Zot replaces the homelab's dependency on external registries (GHCR/ACR) as the destination for its own image pushes, and acts as an on-demand pull-through cache for `ghcr.io`, `mcr.microsoft.com`, and Docker Hub.

## Capabilities

The registry is:

- A single `zot` container on the shared `homelab_net`, reachable internally as `zot:5000` from Caddy. No public host port is published; the only published binding is `127.0.0.1:5000` for SSH-tunnel debugging.
- **Authenticated for push and pull** — it is internet-exposed; anonymous pull would make the pull-through cache an open proxy. Credentials are a single htpasswd user/password fetched from Azure Key Vault (`homelab-bysxdb-kv`) at playbook runtime. No credential is committed.
- A pull-through cache: `sync` extension with on-demand mirrors for `ghcr.io`, `mcr.microsoft.com`, `index.docker.io`, using `preserveDigest: true` + `http.compat: ["docker2s2"]` so digest-pinned pulls and signatures survive mirroring. Upstream content is stored under `/ghcr`, `/mcr`, `/dockerhub` repository prefixes.
- Public via `http://zot.<domain>` → `zot:5000` in the shared Caddyfile (Cloudflare Tunnel terminates TLS at the edge, per ADR 19). The route is declared in the base `docker_services` Caddyfile template **and** ensured idempotently by this workload's `zot_ingress` role (`blockinfile`) — first writer wins.
- Pinned to a released Zot image tag (`v2.1.18`), not `latest`.
- Idempotent: re-running the playbook reports `changed=0` when no template / image / KV change exists.

The full `ghcr.io/project-zot/zot` image is used, with the `search`, `ui`, and `mgmt` extensions enabled by default (web UI + CVE scanning). `config.json` and `htpasswd` are bind-mounted read-only; image data lives in `zot_data_dir`.

## Services

| Service | Image | Port binding | Network | Owned by |
|---|---|---|---|---|
| `zot` | `ghcr.io/project-zot/zot:v2.1.18` | `127.0.0.1:5000:5000` | `homelab_net` (external) | `zot_registry` role |

`zot_ingress` owns the Caddy route only; Caddy itself is deployed by the base `docker_services` role.

## Host on-disk layout

```
/etc/zot/                          # registry config root (templated by zot_registry)
├── config.json                    # storage, http, auth, sync mirror config
├── htpasswd                       # bcrypt htpasswd (role default user, mode 0600)
└── docker-compose.yml

/var/lib/zot/                      # registry blob storage (zot_data_dir)
```

Container paths: config at `/etc/zot/config.json`, htpasswd at `/etc/zot/htpasswd`, storage root `/var/lib/zot` (container path, bind-mounted from `zot_data_dir`).

## Secrets

One secret must exist in the vault declared by `zot_keyvault_name` (default `homelab-bysxdb-kv`):

- `zot-registry-password` — the registry password (`zot_registry_password_secret_name`)

The username is the role default `zot_registry_user: zot` (not a secret). Provision the password with `scripts/New-HomelabZotRegistryCredential.ps1`; the role fetches it at runtime via `azure.azcollection.azure_keyvault_secret` and writes the bcrypt htpasswd file on the host (`/etc/zot/htpasswd`, mode 0600) using the `community.general.htpasswd` module. No `.env` file or plaintext credential is rendered on the host. Rotation = run the script with `-Force`, then re-run the playbook. Only one htpasswd user is supported.

Provisioning steps are in the operational runbook.

## Role Idempotency

`zot_registry` uses `community.docker.docker_compose_v2` with `state: present` and `pull: always`. On the first run:

1. `homelab_net` bridge network is ensured (idempotent with the base playbook — first writer wins).
2. `python3-passlib`/`python3-bcrypt` are installed; the htpasswd entry is written from the KV-sourced password by the idempotent `community.general.htpasswd` module.
3. `config.json` and `docker-compose.yml` are templated; the zot container is deployed.
4. Config/htpasswd changes notify a `zot` container restart.

Subsequent runs with no template, image, or KV change report `changed=0`.

## What's in this folder

- `zot-playbook.yml` — playbook entrypoint.
- `zot_registry/` — role: directories, `python3-passlib`/`python3-bcrypt`, KV password fetch, htpasswd write via the `htpasswd` module, `config.json` + `docker-compose.yml` templates, `homelab_net` ensure, container deploy.
- `zot_ingress/` — role: idempotent `zot.<domain>` site block in the shared Caddyfile + Caddy restart.

## Invoke

    ansible-playbook ansible/workloads/zot/zot-playbook.yml

## Hosts

`cloudlab` (configured at `ansible/host_vars/cloudlab.yml`). The workload targets `cloudlab` first per ADR 13 staging; the physical homelab box is a later port.

## Roles run

1. `zot_registry` — deploys the registry container and config.
2. `zot_ingress` — registers the public route in the shared Caddyfile.

## Vars consumed

- `zot_public_domain` — public DNS suffix for the registry hostname (`zot.<domain>`), default `example.com`, overridden per host.
- `zot_keyvault_name`, `zot_registry_user_secret_name`, `zot_registry_password_secret_name`, `zot_dir`, `zot_data_dir`, `zot_image` — role defaults.
- `zot_caddyfile` — path to the shared Caddyfile (default `/opt/docker/Caddyfile`).

## Operational runbook

For deployment steps, secret provisioning, and the verification checklist, see [`docs/runbooks/20-deploy-zot.md`](../../../docs/runbooks/20-deploy-zot.md).
