# OpenCode workload

## Purpose

A self-contained Ansible recipe that deploys per-project OpenCode server instances on cloudlab. The workload decouples OpenCode deployment from the base host provisioning playbook so adding a new OpenCode project requires no playbook edits, no role inventory changes, and no role resync.

Per ADR 18, OpenCode instances are sandboxed: each project (`homelab`, `prospera`, future) gets its own OpenCode server container, its own persistent data volumes, and its own subdomain. The agent's tools (Bash, file edits, MCP servers) run inside the container; the host is untouched by agent execution.

## Capabilities

Each OpenCode instance is:

- A long-running headless `opencode serve` container exposing the HTTP API + WebUI on port 4096.
- Authenticated via HTTP basic auth (`OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD`); password is fetched from Azure Key Vault `homelab-bysxdb-kv` at playbook runtime. No credential written to the host filesystem.
- Reachable publicly via `<instance>-oc.<domain>` through the dedicated `caddy-opencode` ingress.
- Sandbox-isolated: no host Docker socket mounted, no host filesystem mounts beyond the workspace directory, run as a non-root user inside the container.
- Persistent: per-instance data lives under `/var/lib/opencode/instances/<name>/{data,state,config,workspace}/` on the host, bind-mounted into the container at `~/.local/share/opencode`, `~/.local/state/opencode`, `~/.config/opencode`, and `/workspace`.
- Idempotent: re-running the playbook reports `changed=0` when no template / image / KV change exists.

## Services

| Service | Image | Port binding | Network | Owned by |
|---|---|---|---|---|
| `caddy-opencode` | `caddy:2-alpine` | `127.0.0.1:8090:8080` (debug) | `opencode_net` (external) | `docker_opencode_ingress` role |
| `opencode-<name>` | `ghcr.io/anomalyco/opencode:latest` | none (internal only) | `opencode_net` (external) | `docker_opencode_instances` role |

All OpenCode containers attach only to `opencode_net`.

## Host on-disk layout

```
/etc/opencode/ingress/                  # templated by docker_opencode_ingress
├── Caddyfile
└── docker-compose.yml

/var/lib/opencode/instances/            # data tree root (role default: opencode_instances_dir)
└── <name>/                             # per instance
    ├── data/                           # bind-mounted → ~/.local/share/opencode
    ├── state/                          # bind-mounted → ~/.local/state/opencode
    ├── config/                         # bind-mounted → ~/.config/opencode
    └── workspace/                      # bind-mounted → /workspace
```

Per-instance directories owned by `1000:1000` (matches the typical UID of the `opencode` user inside the upstream image). Verify on the host with `docker run --rm ghcr.io/anomalyco/opencode:latest id` and adjust ownership if mismatched.

## Secrets

A secret named `opencode-<instance-name>-server-password` must exist in the vault declared by `opencode_keyvault_name` (default `homelab-bysxdb-kv`) before applying the playbook. The role fetches it at runtime via `azure.azcollection.azure_keyvault_secret` and injects it as `OPENCODE_SERVER_PASSWORD`. Provisioning steps are in the operational runbook.

No `.env` file is rendered on the host. API keys for model providers are intentionally **not** passed as env vars — they live in the persistent `auth.json` that OpenCode writes under `~/.local/share/opencode/auth.json` on first login.

## Role Idempotency

Both roles use `community.docker.docker_container` / `community.docker.docker_compose_v2` with `state: started` / `state: present` and `pull: true` by default. On the first run:

1. `opencode_net` bridge network is created (whichever role runs first wins; the second is a no-op).
2. `caddy-opencode` is deployed and joined to `opencode_net`.
3. Each OpenCode instance is deployed via `docker_container`.
4. Each instance's `/global/health` endpoint is polled until 200 (retries 12×5s).

Subsequent runs with no template, image, or KV change report `changed=0`. Password rotations trigger `Restart opencode instance` for the affected container.

## What's in this folder

- `opencode-playbook.yml` — playbook entrypoint.
- `docker_opencode_ingress/` — role: deploys `caddy-opencode`, renders per-instance Caddyfile from `host_vars.cloudlab.opencode_instances`.
- `docker_opencode_instances/` — role: ensures per-instance data dirs, fetches passwords from `homelab-bysxdb-kv`, deploys containers via `community.docker.docker_container`.

## Invoke

    ansible-playbook ansible/workloads/opencode/opencode-playbook.yml

## Hosts

`cloudlab` (configured at `ansible/host_vars/cloudlab.yml`). The workload targets `cloudlab` only; homelab deploy is a future concern.

## Roles run

1. `docker_opencode_ingress` — verifies `opencode_net`, runs Caddyfile template, deploys `caddy-opencode` via docker compose.
2. `docker_opencode_instances` — reads `opencode_instances` from host_vars, ensures per-instance data dirs, fetches passwords from KV, deploys containers, polls `/global/health`.

Both roles idempotently declare `opencode_net`. The main `playbook.yml` also declares it via pre_tasks. First writer wins.

## Vars consumed

- `opencode_instances` — list of `{name: ...}` rows from host_vars. Adding an instance = one row.
- `opencode_public_domain` — declared in each role's defaults (sanitized) and overridden per host.
- `opencode_keyvault_name`, `opencode_password_secret_template`, `opencode_instances_dir` — role defaults.

## Sequencing note

Run after the base playbook has been applied (`common`, `security`, `azure_arc`, `docker_host`, `docker_services`). The OpenCode workload does not depend on the base playbook beyond network attachment.

## Operational runbook

For deployment steps, secret provisioning, and the verification checklist, see [`docs/runbooks/17-deploy-opencode-on-cloudlab.md`](../../../docs/runbooks/17-deploy-opencode-on-cloudlab.md).

