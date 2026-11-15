# DevContainer Dependency Cadence — Weekly Dependabot for Features, Quarterly Review of Base and Pins

**Date:** 2026-11-15  
**Status:** Proposed  

---

## Context

PR #204 modernized the devcontainer (Ubuntu 26.04 base, locked feature digests, ansible-core
2.22 via a pinned pip venv) — but without a maintenance cadence those pins rot on predictable
schedules: apt caps ansible-core per Ubuntu release (2.16 was EOL before #204), feature
digests age, MCR stops building images for EOL OS versions, and ansible-core maintains each
line only ~4 releases (~2 years; the `INJECT_FACTS_AS_VARS` removal lands in 2.24, ~Nov 2027).
Analysis and sources: [research 58](../research/58-devcontainer-dependency-maintenance.md).

## Decision

1. **Features + lock file: automated, weekly.** `.github/dependabot.yml` enables the
   `devcontainers` ecosystem (weekly schedule); Dependabot bumps feature versions in
   `.devcontainer/devcontainer.json` and regenerates `devcontainer-lock.json` in one grouped
   PR. Features are pinned to full versions in `devcontainer.json` so bumps show as clean diffs.
2. **Base image: floating LTS tag, quarterly manual review.** Keep `ubuntu26.04` (not a digest
   pin — a frozen base gets no security patches). Move only on LTS transitions (26.04 → 28.04 in
   Apr 2028); interim releases are rejected (9-month support, same Python major as the LTS).
3. **Script pins (`setup-ansible.sh`): bump every ansible-core major (~6 months)**, never more
   than one major behind latest; update the skip-path version grep together with the pin.
4. **`ansible/requirements.yml` exact pins: quarterly review**, bumped only deliberately with a
   live playbook run after CR (ADR 22) — the pins exist because unbounded ranges broke Key
   Vault lookups and OPNsense API drift.
5. **Event-driven bumps**: security advisories affecting the base or tools (the floating tag
   picks up base patches without a PR), and ansible-core deprecation removals (2.24).
6. **Verification stays local (ADR 32)**: rebuild the container (postCreate prints installed
   versions), `ansible-lint` any changed role, `--syntax-check` the base playbook. No hosted CI.

## Consequences

- Positive: no silent dependency rot; small reviewable PRs; base image keeps receiving security
  rebuilds via the floating LTS tag; ansible-core pin can never be more than one major behind.
- Negative: a weekly Dependabot PR to triage (usually one-line version bumps); each accepted
  bump costs one local container rebuild before merge.

### Alternatives Considered

- **Monthly Dependabot** — rejected: feature bugfix/security fixes would wait up to a month.
- **Digest-pinned base image** — rejected: byte-reproducible but frozen, no security patches;
  and MCR stops rebuilding EOL OS tags anyway, so pinning an interim release buys nothing.
- **Manual-only, ad hoc reviews** — rejected: this is exactly how the container ended up on
  EOL ansible-core 2.16 via apt before PR #204.
- **Hosted-CI validation of dep bumps** — rejected per [ADR 32](32-no-hosted-ci.md); Dependabot
  is a PR bot, not CI, and verification stays a local rebuild.
