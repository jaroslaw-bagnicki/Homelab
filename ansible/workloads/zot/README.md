# Zot workload

## Purpose

A self-contained Ansible recipe that deploys the **Zot OCI container registry** (`ghcr.io/project-zot/zot`) on cloudlab, exposing a public registry at `zot.<domain>` and caching upstream pulls. Per issue #50, Zot replaces the homelab's dependency on external registries (GHCR/ACR) as the destination for its own image pushes, and acts as an on-demand pull-through cache for `ghcr.io`, `mcr.microsoft.com`, and Docker Hub.

## Capabilities

The registry is:

- A single `zot` container on the shared `homelab_net`, reachable internally as `zot:5000` from Caddy. No public host port is published; the only published binding is `127.0.0.1:5000` for SSH-tunnel debugging.
- **Authenticated for push and pull** — it is internet-exposed; anonymous pull would make the pull-through cache an open proxy. Credentials are a single htpasswd user/password fetched from Azure Key Vault (`homelab-bysxdb-kv`) at playbook runtime. No credential is committed.
- A pull-through cache: `sync` extension with on-demand mirrors for `ghcr.io`, `mcr.microsoft.com`, `index.docker.io`, using `preserveDigest: true` + `http.compat: ["docker2s2"]` so digest-pinned pulls and signatures survive mirroring. Upstream content is stored under `/ghcr`, `/mcr`, `/dockerhub` repository prefixes.
- Public via `zot.<domain>` through the shared Caddyfile (Cloudflare Tunnel terminates TLS at the edge, per ADR 19). Routing is declared in the base `docker_services` Caddyfile template and applied by the base playbook — see [External access](#external-access).
- Pinned to a released Zot image tag (`v2.1.18`), not `latest`.
- Idempotent: re-running the playbook reports `changed=0` when no template / image / KV change exists.

The full `ghcr.io/project-zot/zot` image is used, with the `search`, `ui`, and `mgmt` extensions enabled by default (web UI + CVE scanning). `config.json` and `htpasswd` are bind-mounted read-only; image data lives in `zot_data_dir`.

## Services

| Service | Image | Port binding | Network | Owned by |
|---|---|---|---|---|
| `zot` | `ghcr.io/project-zot/zot:v2.1.18` | `127.0.0.1:5000:5000` | `homelab_net` (external) | `zot_registry` role |

Caddy itself is deployed by the base `docker_services` role; this workload does not touch it.

## External access

By default the zot container listens only on `homelab_net` (`zot:5000`), published on the host loopback (`127.0.0.1:5000`) for debugging; no public port is exposed. Three options to expose it publicly:

### Option A — Reverse proxy via Caddy (repo default)

Routing is declared once in the base `docker_services` Caddyfile template and applied by the base playbook (`ansible/playbooks/playbook.yml`):

```caddyfile
http://zot.example.com {
    reverse_proxy zot:5000
}
```

With the Cloudflare Tunnel sending `zot.example.com` → `http://caddy:80` (see [runbook 20 §3](../../../docs/runbooks/20-deploy-zot.md)), the path is: browser → CF edge → cloudflared → `caddy:80` → `zot:5000`. Caddy is restarted by the base role's handler when the template changes, so the base playbook must run before/after the workload to make the route live.

### Option B — zot native HTTPS on host port 443

Enable TLS in zot itself and bind it to the host's public port 443 — no Caddy, no tunnel needed:

```jsonc
// config.json — http section
"http": {
    "port": "443",
    "tls": {
        "cert": "/etc/zot/certs/server.crt",
        "key":  "/etc/zot/certs/server.key"
    }
}
```

```yaml
# docker-compose.yml
ports:
  - "443:443"
```

The certificate files must be mounted into the container and provisioned out-of-band — zot does not do ACME (e.g. a Cloudflare Origin CA cert, or Let's Encrypt via certbot). Trade-offs: requires opening inbound TCP 443 on the host (diverges from ADR 19's tunnel-only ingress), manual cert provisioning and renewal, and the DNS record should point at the host IP (grey-cloud) or use CF proxy with SSL mode `Full (strict)`.

### Option C — Cloudflare Tunnel direct to zot

Point the Cloudflare Tunnel public hostname straight at the container (service `HTTP` → `zot:5000`) and skip Caddy. No Caddyfile change needed. Trade-off: the origin lives in the Cloudflare dashboard rather than the declarative Caddyfile, and zot bypasses Caddy as the single routing/security layer (ADR 20).

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

The username is the role default `zot_registry_user: zot-admin` (not a secret). This single user is granted **global admin** via `accessControl.adminPolicy` in `config.json` (in addition to the `**` repository policy), so it has full read/create/update/delete on any repository and admin status for the management API/UI. Provision the password with `scripts/New-HomelabZotRegistryCredential.ps1`; the role fetches it at runtime via `azure.azcollection.azure_keyvault_secret` and writes the bcrypt htpasswd file on the host (`/etc/zot/htpasswd`, mode 0600) using the `community.general.htpasswd` module. No `.env` file or plaintext credential is rendered on the host. Rotation = run the script with `-Force`, then re-run the playbook. Only one htpasswd user is supported.

Provisioning steps are in the operational runbook.

## Role Idempotency

`zot_registry` uses `community.docker.docker_compose_v2` with `state: present` and `pull: always`. On the first run:

1. `homelab_net` bridge network is ensured (idempotent with the base playbook — first writer wins).
2. `python3-passlib`/`python3-bcrypt` are installed; the htpasswd entry is written from the KV-sourced password by the idempotent `community.general.htpasswd` module.
3. `config.json` and `docker-compose.yml` are templated; the zot container is deployed.
4. Config/htpasswd changes notify a `zot` container restart.

Subsequent runs with no template, image, or KV change report `changed=0`.

> `python3-passlib`/`python3-bcrypt` are the `community.general.htpasswd` module's required **target-side** Python dependencies — installing the `community.general` collection only ships the module code to the controller. Without them on the host, the module fails with a "missing required library `passlib`" error.

## What's in this folder

- `zot-playbook.yml` — playbook entrypoint.
- `zot_registry/` — role: directories, `python3-passlib`/`python3-bcrypt`, KV password fetch, htpasswd write via the `htpasswd` module, `config.json` + `docker-compose.yml` templates, `homelab_net` ensure, container deploy.

## Invoke

    ansible-playbook ansible/workloads/zot/zot-playbook.yml

## Hosts

`cloudlab` (configured at `ansible/host_vars/cloudlab.yml`). The workload targets `cloudlab` first per ADR 13 staging; the physical homelab box is a later port.

## Roles run

1. `zot_registry` — deploys the registry container and config.

## Vars consumed

- `zot_keyvault_name`, `zot_registry_password_secret_name`, `zot_dir`, `zot_data_dir`, `zot_image` — role defaults.
- `zot_registry_user` — htpasswd username (role default `zot-admin`), the global admin (`adminPolicy`) and `**` repository policy holder, used by `config.json` and the `htpasswd` module.
- `zot_public_domain` — public DNS suffix for the registry hostname (`zot.<domain>`), default `example.com`, overridden per host; consumed by the base `docker_services` Caddyfile template for the route.

## Operational runbook

For deployment steps, secret provisioning, and the verification checklist, see [`docs/runbooks/20-deploy-zot.md`](../../../docs/runbooks/20-deploy-zot.md).

## References

- [Zot — User Authentication and Authorization](https://zotregistry.dev/v2.1.18/articles/authn-authz/) — authentication methods and the `accessControl` / `adminPolicy` authorization model (admin users can act on any repository).
- [Zot — `mgmt` extension README](https://github.com/project-zot/zot/blob/main/pkg/extensions/README_mgmt.md) — the `GET /v2/_zot/ext/mgmt` config endpoint: stripped config for all users, full config for admins (not implemented yet).
