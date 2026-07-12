# OpenCode workload

## Purpose

A self-contained Ansible recipe that deploys per-project OpenCode server instances on cloudlab, behind the existing Caddy + Cloudflare Tunnel ingress. The workload decouples OpenCode deployment from the base host provisioning playbook so adding a new OpenCode project requires no playbook edits, no role inventory changes, and no role resync.

Per ADR 18, OpenCode instances are sandboxed: each project (`homelab`, `prospera`, future) gets its own OpenCode server container, its own persistent data volumes, and its own subdomain. The agent's tools (Bash, file edits, MCP servers) run inside the container; the host is untouched by agent execution.

## Capabilities

Each OpenCode instance is:

- A long-running headless `opencode serve` container exposing the HTTP API + WebUI on port 4096.
- Authenticated via HTTP basic auth (`OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD`); password is fetched from Azure Key Vault `homelab-bysxdb-kv` at playbook runtime. No credential written to the host filesystem.
- Reachable publicly via `<instance>-oc.<domain>` through the dedicated `caddy-opencode` ingress and the existing Cloudflare Tunnel wildcard.
- Sandbox-isolated: no host Docker socket mounted, no host filesystem mounts beyond the workspace directory, run as a non-root user inside the container.
- Persistent: per-instance data lives under `/var/lib/opencode/instances/<name>/{data,state,config,workspace}/` on the host, bind-mounted into the container at `~/.local/share/opencode`, `~/.local/state/opencode`, `~/.config/opencode`, and `/workspace`.
- Idempotent: re-running the playbook reports `changed=0` when no template / image / KV change exists.

## What's in this folder

- `opencode_playbook.yml` — playbook entrypoint.
- `docker_opencode_ingress/` — role: deploys `caddy-opencode`, renders per-instance Caddyfile from `host_vars.cloudlab.opencode_instances`.
- `docker_opencode_instances/` — role: ensures per-instance data dirs, fetches passwords from `homelab-bysxdb-kv`, deploys containers via `community.docker.docker_container`.

## Invoke

    ansible-playbook ansible/workloads/opencode/opencode_playbook.yml

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

## Troubleshooting

See `docs/runbooks/17-deploy-opencode-on-cloudlab.md` §7 for the verification checklist and full operational steps.
