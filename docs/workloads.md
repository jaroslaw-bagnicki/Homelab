# Workloads

Each workload in this repository is a self-contained recipe, runnable independently via `ansible-playbook ansible/workloads/<workload>/<workload>.yml`.

## Convention rules

- Workload recipe lives at `ansible/workloads/<workload>/<workload>.yml` next to its roles and ansible-side README.
- Standalone playbook entrypoint declared in the workload folder.
- Workloads do not import each other.
- Workloads do not declare shared pre_tasks in the base playbook.
- Adding a new workload:
  1. Create the workload folder under `ansible/workloads/<workload>/`.
  2. Add the playbook entrypoint, role recipes, and ansible-side README inside it.
  3. Add a row to the "Index" table below.
  4. Add a row to `README.md` "What's Next" or "What's Done".
  5. Optionally: a runbook at `docs/runbooks/NN-deploy-<workload>.md`.

## Index

| Workload | Path | Purpose |
|---|---|---|
| OpenCode | `ansible/workloads/opencode/opencode_workload.yml` | Per-project OpenCode server instances on cloudlab's dedicated `opencode_net`. See [runbook 17](runbooks/17-deploy-opencode-on-cloudlab.md). |
