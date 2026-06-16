# Ansible for Host Configuration Management

**Date:** 2026-06-13  
**Status:** Accepted

---

## Context

The homelab server (Lenovo ThinkCentre M910q Tiny, Ubuntu 24.04 LTS) was initially set up via imperative shell commands captured in Markdown runbooks (`runbooks/1-init.md`, `runbooks/2-docker.md`, etc.). This approach has several shortcomings:

- **No idempotency** — re-running a runbook after partial failure requires manual recovery
- **No drift detection** — there is no way to verify the host still matches the documented state after ad-hoc fixes
- **Disaster recovery is fragile** — rebuilding from scratch requires following the runbooks step by step with manual intervention
- **Migration to Ubuntu 24.04 from 26** surfaced the pain: no automated way to reprovision the host after a clean OS install

The research thread (see `research/13-ansible-adoption.md`) evaluated several configuration management approaches against the constraints of a single-node Linux homelab with Docker Compose, Azure Arc, and a planned future migration to k3s.

## Decision

**Adopt Ansible** as the declarative configuration management tool for the homelab host. The Ansible playbook(s) will live in the existing Homelab Git repository, replacing the imperative runbooks as the source of truth for host state.

Key elements of the approach:

- **Start flat, not modular.** A single `playbook.yml` with flat tasks (no role over-engineering) — structure emerges when a second host or readability demands it.
- **Inventory** — a single `inventory.ini` pointing at the one Lenovo Tiny.
- **Scope** — OS packages, SSH config, UFW firewall, Docker engine, storage directories (bind-mount paths), and Azure Arc agent registration. Stateful data backup/restore is handled separately by Restic (see `260613-backup-strategy-restic-blob.md`).
- **Ansible manages the host; Azure Arc manages the cloud side.** Clean separation: Ansible bootstraps and configures the OS before Arc enrolment; after enrolment, Arc handles monitoring (AMA), update management, and policy.
- **Docker Compose deployment** delegated to `community.docker.docker_compose_v2` module in a late playbook step — keeps the Compose files as the workload definition.

## Consequences

- **Positive.** Full DR from clean Ubuntu is a single `ansible-playbook` invocation. No more manual step-by-step recovery.
- **Positive.** Idempotent runs — re-applying the playbook on a drifted host corrects state without manual audit.
- **Positive.** The same playbook structure works unchanged when migrating to k3s — only the `docker_host` role gets swapped for a k3s role; `common` and `security` stay untouched.
- **Positive.** Existing Markdown runbooks can serve as direct input for playbook authoring.
- **Negative.** Discipline cost — every ad-hoc SSH fix must be reflected back in the playbook, or Git drifts from reality. Single-node Ansible has no automatic enforcement.
- **Negative.** Ansible adds a tool dependency — the control machine needs Python + Ansible installed, and the target needs a non-root user with passwordless sudo.
- **Negative.** For a single host, the Ansible abstraction layer (inventory, playbook, variable precedence) adds more ceremony than a well-structured bash script would — accepted as a reasoned trade-off for DR repeatability and future multi-host readiness.

### Alternatives Considered

- **Azure Machine Configuration (Guest Configuration via DSC).** Rejected because the Linux DSC ecosystem is effectively unmaintained. No community modules, must package `.zip` artifacts to Azure Storage, enforce via Azure Policy — all overhead with no benefit for a single-node homelab.
- **Keep imperative shell scripts / runbooks.** Rejected because they are not idempotent, cannot detect drift, and require manual supervision during DR. The runbooks remain as reference but are superseded by the playbook as the source of truth for automation.
- **Automated reverse-engineering tools** (Ansible-Bender, Blueprint). Rejected — they produce noisy, non-declarable output with thousands of irrelevant lines. Manual authoring from `apt-mark showmanual` and `docker-compose.yml` analysis yields cleaner, maintainable code.

---

**Reference:** `research/13-ansible-adoption.md`
**Supersedes:** runbooks as the automation source of truth (`runbooks/1-init.md` etc. retain reference value only)
