# OpenCode workload

Self-contained Ansible recipe for the OpenCode per-project server workload on cloudlab.

## What's in this folder

- `opencode_workload.yml` — playbook entrypoint.
- `docker_opencode_ingress/` — role: deploys `caddy-opencode`, renders per-instance Caddyfile from `host_vars.cloudlab.opencode_instances`.
- `docker_opencode_instances/` — role: ensures per-instance data dirs, fetches passwords from `homelab-bysxdb-kv`, deploys containers via `community.docker.docker_container`.

## Invoke

    ansible-playbook ansible/opencode_workload/opencode_workload.yml

## Hosts

`cloudlab` (configured at `ansible/host_vars/cloudlab.yml`).

## Roles run

1. `docker_opencode_ingress` — verifies `opencode_net`, runs Caddyfile template, deploys `caddy-opencode` via docker compose.
2. `docker_opencode_instances` — reads `opencode_instances` from host_vars, ensures per-instance data dirs, fetches passwords from KV, deploys containers, polls `/global/health`.

Both roles idempotently declare `opencode_net`. The main `playbook.yml` also declares it. First writer wins.

## Vars consumed

- `opencode_instances` — list of `{name: ...}` rows from host_vars.
- `opencode_public_domain` — declared in each role's defaults (sanitized) and overridden per host.
- `opencode_keyvault_name`, `opencode_password_secret_template`, `opencode_instances_dir` — role defaults.

## Sequencing note

Run after the base playbook has been applied (`common`, `security`, `azure_arc`, `docker_host`, `docker_services`). The OpenCode workload does not depend on the base playbook beyond network attachment.

## Troubleshooting

See `docs/runbooks/17-deploy-opencode-on-cloudlab.md` §7 for the verification checklist and full operational steps.
