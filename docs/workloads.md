# Workloads

Each workload in this repository is a self-contained recipe, runnable independently via `ansible-playbook ansible/workloads/<workload>/<workload>_playbook.yml`.

## Convention rules

- Workload recipe lives at `ansible/workloads/<workload>/<workload>_playbook.yml` next to its roles and ansible-side README.
- Standalone playbook entrypoint declared in the workload folder.
- Workloads do not import each other.
- Workloads do not declare shared pre_tasks in the base playbook.
- Adding a new workload:
  1. Create the workload folder under `ansible/workloads/<workload>/`.
  2. Add the playbook entrypoint (`<workload>_playbook.yml`), role recipes, and an ansible-side README inside it.
  3. Add a row to the "Index" table below.
  4. Add a row to `README.md` "What's Next" or "What's Done".
  5. Optionally: a runbook at `docs/runbooks/NN-deploy-<workload>.md`.

## Index

| Workload | Path | Purpose | Docs |
|---|---|---|---|
| OpenCode | `ansible/workloads/opencode/opencode_playbook.yml` | Per-project OpenCode server instances on cloudlab's dedicated `opencode_net`. | [Workload README](../ansible/workloads/opencode/README.md) · [Runbook 17](runbooks/17-deploy-opencode-on-cloudlab.md) |
