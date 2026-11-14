# AI Model Split — DeepSeek V4.1 Flash Stays the Daily Driver via Mistral, Large 4 for Heavy Tasks

**Date:** 2026-11-14  
**Status:** Accepted  
**Supersedes:** the provider note in [ADR 15](15-copilot-desktop-agentic.md) / [ADR 17](17-adopt-opencode.md) — the endpoint moves from `https://api.deepseek.com/v1` to `https://api.mistral.ai/v1`; the model does not change  
**Analysis:** [idea 16](../ideas/16-ai-model-mistral-large-4.md) · tracked in [#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179) · BYOK setup: [runbook 44](../runbooks/44-copilot-mistral-byok.md)

---

## Context

Every doc, Ansible role, Bicep module and script in this repo is written with an AI agent, and one model
was a silent single point of dependency ([idea 16](../ideas/16-ai-model-mistral-large-4.md), #179). The
question was whether Mistral Large 4 should displace DeepSeek V4.1 Flash as the daily driver. Both models
are served by Mistral's platform, so one **Mistral Pro** subscription ($15/mo included usage shared across
Studio, API and Vibe Code) funds candidate and control alike.

## Decision

**Use both models, on one Mistral billing account:**

- **DeepSeek V4.1 Flash (`deepseek-v4-1-flash-1017`) remains the daily driver**, now served through
  `https://api.mistral.ai/v1` under the Pro subscription — the **DeepSeek direct subscription is
  retired**. In `opencode.json` the `deepseek` provider gives way to a `mistral` provider with both model
  presets (key via `MISTRAL_API_KEY`); the Copilot BYOK entry moves from runbook 13 §2 to
  [runbook 44](../runbooks/44-copilot-mistral-byok.md).
- **Mistral Large 4 (`mistral-large-4`) handles the heavy, reasoning-heavy tasks** — long authoring — via
  Mistral Vibe (`mistral-large-4-0` sessions) and Copilot/VS Code BYOK. Its 2.3× input / 1.75× output /
  10× cached-input premium rules it out as the everyday model at any quality.
- **GLM 5.3 / GLM 5.3 Flash (Mistral-hosted)** are queued for the same fixed-method A/B when budget allows.

## Consequences

- One key, one usage report: daily work, ML4 heavy tasks and any future A/B all meter on the Pro plan
  (then pay-as-you-go credits).
- The Mistral-hosted DeepSeek card is badged **public preview** + third-party; accepted for a single
  billing relationship, with the DeepSeek direct key as the fallback if the preview degrades.
- Evidence basis, recorded honestly in idea 16: the formal four-task side-by-side did not run; the split
  rests on the 2026-11-07/08 API probes on #179 plus hands-on use. The fixed method in idea 16 stays as
  the re-check if the split is revisited.

### Alternatives Considered

- **Large 4 as sole daily driver** — rejected: 2.3× input / 10× cached premium with no measured
  task-success advantage (the formal A/B never ran).
- **Keep DeepSeek on its direct API as a second billing relationship** — rejected by the owner: the
  preview endpoint is accepted so one account carries everything.
- **Outcome only in idea 16, no ADR** — rejected on review (PR #198): the ideas lifecycle reserves ✅ Done
  for ADR-archived decisions.
