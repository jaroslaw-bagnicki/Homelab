# No Hosted CI — Verification Stays Local

**Date:** 2026-09-16
**Status:** Accepted

---

## Context

The repo merges a few times a week through one flow — feature branch → push → PR → review → merge — operated by a single person in spare time (ADR 11's "zero ceremony" requirement).

Verification is already defined, and it is entirely **local**:

- `ansible-lint` on every changed role before committing, with lint failures treated as fatal (`AGENTS.md` "Ansible Verification").
- A live `ansible-playbook … --diff` run against the target host before merge, and a re-run after merge so the host matches the merged code — because task bugs (idempotency, output parsing, module parameters) only surface at runtime.
- Per-procedure completion checklists inside the runbooks; runbook 29 tags each outstanding row with the issue that owns it.
- Smoke-test scripts for the OpenCode images (`docker/*/tests/verify-*.sh`), run by hand when an image changes.

The first quality assessment (2026-09-13) recorded the absence of `.github/workflows` as finding **3.5** — a *High* antipattern — with a CI workflow as its recommendation. On review the operator ruled that out: an assessment is the wrong place for the decision, and the only check a pipeline would meaningfully contribute is `ansible-lint`, which already runs locally in seconds.

That ruling needs an authoritative home rather than a paragraph in a report. `docs/reports/README.md` is explicit — reports are "point-in-time snapshots, not policy", and "not authoritative for design rationale". A decision recorded only there is re-derived by the next audit or agent session, which is exactly what had to be corrected by hand. Hence this ADR.

## Decision

**Do not adopt a hosted CI service. Verification stays a local, documented, pre-commit discipline.**

- No `.github/workflows` — or any other hosted pipeline — is added.
- `ansible-lint` on changed roles remains the one automated check, enforced by convention, run locally.
- The `docker/*/tests/verify-*.sh` scripts stay manual; they are run when an image changes, not on every push.
- `AGENTS.md` and `.github/copilot-instructions.md` carry a one-line pointer here, so an agent session does not re-propose a pipeline.
- Assessment findings 3.5 and 4.1 are re-pointed at this ADR and no longer counted as a finding or a gap.

**Scope is CI — build and test validation — not deployment automation.** The GitOps question for the k3s cluster (ArgoCD, Flux, or manual `kubectl apply`) stays open in ADR 22 and is unaffected by this decision.

## Consequences

- **No pipeline to maintain** — no workflow files, no runner images, no action-version churn, no second place where the toolchain is pinned.
- **One toolchain, one machine** — `ansible-lint` runs in the dev container the operator already works in, against the same collections pinned in `requirements.yml`.
- **Failures are seen where they are fixed**, in the terminal, rather than relayed through a CI log.
- **No CI cost or build minutes**, and nothing about the repo leaves it.
- **No enforced gate — this is the accepted cost.** Nothing blocks a merge that skips the lint step; compliance rests on operator discipline plus PR-time Copilot review.
- **No clean-room check.** A workflow would run the playbooks in an environment that is not the dev container, so environment-specific assumptions can go unnoticed. Partly offset by the live `--diff` runs against cloudlab before each merge.
- **No build record attached to a commit.** The PR conversation is the audit trail.
- **The calculus assumes one person.** The compensating controls above all depend on the operator knowing the rules — a second contributor would change this decision, not just its implementation.

**Revisit if:** a second contributor joins; a check becomes necessary that cannot be run locally (for example a reproducible build artefact); or a workload's release needs an auditable build record.

### Alternatives Considered

None — and that is recorded deliberately. This is a **scope** decision, not a vendor comparison: CI as a category was declined because the only check it would add (`ansible-lint` on changed roles) is already a local pre-commit rule. No CI product was assessed against a need, so none is listed as rejected.

---

## References

- [ADR 22 — Migrate Homelab Workloads to Kubernetes (k3s + Azure Arc)](22-k3s-arc-homelab.md) — the GitOps question this ADR deliberately does not pre-empt
- [ADR 11 — Ticketing System: GitHub Issues](11-ticketing-github-issues.md) — the "zero ceremony for a single-person project" requirement this follows
- [ADR 10 — Ansible for Host Configuration Management](10-ansible-host-config.md) — the local-discipline trade-off it also accepts
- [Quality assessment 2026-09-13](../reports/260913-quality-assessment.md) — findings 3.5 and 4.1, now re-pointed here
- `AGENTS.md` "Ansible Verification" — the local rules this decision keeps as the standard
