# Workloads

Each workload in this repository is a self-contained recipe, runnable independently via `ansible-playbook ansible/workloads/<workload>/<workload>-playbook.yml`.

## Convention rules

- Workload recipe lives at `ansible/workloads/<workload>/<workload>-playbook.yml` next to its roles and ansible-side README.
- Standalone playbook entrypoint declared in the workload folder.
- Workloads do not import each other.
- Workloads do not declare shared `pre_tasks` in other workloads. The base `playbook.yml` may declare `pre_tasks` for shared resources (e.g. the `opencode_net` Docker network) that multiple workloads depend on — this is a base-setup concern, not a workload concern.
- Adding a new workload:
  1. Create the workload folder under `ansible/workloads/<workload>/`.
  2. Add the playbook entrypoint (`<workload>-playbook.yml`), role recipes, and an ansible-side README inside it.
  3. Add a row to the "Index" table below.
  4. Add a row to `docs/overview.md` "What's Next", and a `CHANGELOG.md` entry on completion.
  5. Optionally: a runbook at `docs/runbooks/NN-deploy-<workload>.md`.

## Index

| Workload | Path | Purpose | Docs |
|---|---|---|---|
| OpenCode | `ansible/workloads/opencode/opencode-playbook.yml` | Per-project OpenCode server instances on cloudlab's dedicated `opencode_net`. | [Workload README](../ansible/workloads/opencode/README.md) · [Deploy — Runbook 17](runbooks/17-deploy-opencode-on-cloudlab.md) · [Provision — Runbook 18](runbooks/18-provision-opencode-instance.md) |
| Zot | `ansible/workloads/zot/zot-playbook.yml` | Self-hosted Zot OCI container registry on cloudlab's `homelab_net` — htpasswd auth from AKV, on-demand pull-through cache for GHCR/mcr/Docker Hub, public at `zot.<domain>` via Cloudflare Tunnel + Caddy. | [Workload README](../ansible/workloads/zot/README.md) · [Deploy — Runbook 20](runbooks/20-deploy-zot.md) |
