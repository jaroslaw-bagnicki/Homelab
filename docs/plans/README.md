# Plans

[← Back to docs](../README.md)

Multi-stage rollout plans — the **order** in which workstreams are built, and the exit gate of each
stage. A plan is sequencing only: design authority stays with the [ADRs](../decisions/README.md), and
where a plan and an ADR disagree the ADR wins.

| Plan | Scope | Status |
|---|---|---|
| [02 — Kodus (Kody) code-review POC](02-kodus-code-review-poc.md) | Self-hosted Kody in k3s on `lab` with `mistral-large-4` BYOK as the PR reviewer, A/B vs Copilot CR; exit gate = adoption ADR — [#190](https://github.com/jaroslaw-bagnicki/Homelab/issues/190) · [idea 18](../ideas/18-copilot-cr-cost-alternatives.md) · [research 54](../research/54-external-code-review-delegation.md) | 📋 Planned |
| [01 — Identity and access stack](01-identity-and-access-stack.md) | SSH host and agent certificates ([#161](https://github.com/jaroslaw-bagnicki/Homelab/issues/161)) → FreeIPA ([#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164)) → Authentik ([#165](https://github.com/jaroslaw-bagnicki/Homelab/issues/165)) → human certificates ([#166](https://github.com/jaroslaw-bagnicki/Homelab/issues/166)) → workload identity ([#168](https://github.com/jaroslaw-bagnicki/Homelab/issues/168)) | 🔨 Active |
