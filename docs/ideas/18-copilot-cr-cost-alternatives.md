# Idea 18 — Alternatives to Copilot Code Review After the 2026 Usage-Based Billing

> Every PR in this repo is written by an AI agent and reviewed by **GitHub Copilot code review** before a
> human merges it. Since GitHub changed how that review is billed (2026‑06‑01, refined 2026‑11‑06), the
> operator observes some reviews costing **2–3× the implementation work itself** — token-metered AI credits
> × a four-model "Balanced" council, plus Actions minutes on private repos. That is not acceptable, and
> the reviewer is worth re-examining like the daily model was in [idea 16](16-ai-model-mistral-large-4.md).

**Status**: 🔨 **POC running direction — Kodus (Kody) self-hosted on `cloudlab` with `mistral-large-4` BYOK**, per [runbook 46](../runbooks/46-poc-kodus-code-review.md), tracked in [#190](https://github.com/jaroslaw-bagnicki/Homelab/issues/190) (2026‑11‑08); the analysis is in [research 54](../research/54-external-code-review-delegation.md). No ADR — the POC decides.
**Date**: 2026‑11‑08
**Sources**: operator report, 2026‑11‑08 ("some CR cost 2–3× of the implementation cost after the rollout of
changes how it works — not acceptable, seek alternatives") · [research 54](../research/54-external-code-review-delegation.md)
(2026‑11‑08 web research with full source list) · [GitHub Blog — usage-based billing](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/)
· [changelog 2026‑06‑01](https://github.blog/changelog/2026-06-01-updates-to-github-copilot-billing-and-plans/) ·
[changelog 2026‑11‑06](https://github.blog/changelog/2026-11-06-copilot-code-review-api-management-and-review-overview-updates/) (Balanced = 3 reviewer models + 1 combiner)
**Related**: [ADR 32](../decisions/32-no-hosted-ci.md) (no hosted CI in this repo) · [idea 16](16-ai-model-mistral-large-4.md) +
[#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179) (the model A/B this would reuse) ·
[runbook 44](../runbooks/44-copilot-mistral-byok.md) (Mistral BYOK — ML4 in VS Code chat via the Responses API path since 2026-11-08, [#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179)#issuecomment-6719695584)) ·
[ADR 15](../decisions/15-copilot-desktop-agentic.md) (Copilot BYOK pattern)

---

## Context

The billing change is documented in [research 54](../research/54-external-code-review-delegation.md) §1: PRUs
became AI Credits ($0.01 each, per token including cached) on 2026‑06‑01; code review on **private** repos
also bills Actions minutes; and from 2026‑11‑06 the default **Balanced** effort runs **four model passes** per
review. GitHub estimates $0.25–$5 of credits per review. On agent-generated PRs with large diffs, review cost
overtaking implementation cost is therefore not a bug — it is the new meter meeting this repo's PR shape.

## Options

| # | Option | Cost shape | Notes |
|---|---|---|---|
| A | **Stay on Copilot, cap it** — lower effort per repo, disable automatic reviews, set an AI-credit spending limit | still per-token, but bounded | zero migration; the 2026‑11‑06 API can manage effort/policy per repo; keeps the reviewer that already knows the repo |
| B | **Flat-rate third-party bot** (CodeRabbit free-for-OSS / ~$24 Pro, Greptile ~$30, Qodo ~$30) | flat per seat | predictable on big PRs; but the app reads the whole repo (vendor cloud) — fine for this public repo, a real question for private ones |
| C | **BYO-model reviewer** — own workflow/webhook calling `api.mistral.ai` (`mistral-large-4` ~$0.05–0.30/review at cache reuse) or a local LLM (~free) | per token, ~10–50× cheaper than Copilot worst case | **conflicts with ADR 32** if committed as CI here — run ad hoc instead; `appleboy/LLM-action` speaks the Mistral endpoint natively |
| D | **Local agent review, ad hoc** — Vibe/OpenCode + GitHub MCP: `gh pr diff` → review → post comments | per token to your provider only | zero new infrastructure; already works today ([runbook 44](../runbooks/44-copilot-mistral-byok.md)); human still merges |
| E | **Kodus/Kody self-hosted as the CR service** — AGPLv3, BYOK zero-markup, any OpenAI-compatible endpoint incl. Mistral | LLM tokens only (~$0.05–0.30/review for ML4) | **chosen for the POC** — [runbook 46](../runbooks/46-poc-kodus-code-review.md); full review pipeline (webhook, Kody Rules, dashboard), not just a diff paste |

## Recommendation

**Measure first, then decide in writing.** Sequence with an exit at every step:

1. **Read the bill** — per-PR AI-credit and Actions-minute spend from the Copilot usage/billing reports on
   this repo and the private ones; confirm the 2–3× cases and which PRs trigger them (diff size, auto vs
   manual review). Two minutes of settings (option A) may already bound the worst case: spending limit +
   effort lowered to the minimum on this repo.
2. **Bounded A/B, reusing idea 16's method** — same PR reviewed by (a) Copilot at current settings,
   (b) `mistral-large-4` via the API (one Mistral Pro key serves it and the DeepSeek control, #179), on
   identical starting commits; judge on findings that survive human review, retries, and **cost per merged
   PR** — not on token price alone.
3. **Decide in writing** — ADR only if a non-Copilot reviewer wins; otherwise record the outcome in
   [research 54](../research/54-external-code-review-delegation.md) and retire this idea. Landing spots:
   Copilot capped (A) + local Vibe review (D) as the cheap second pass; a flat-rate bot (B) if this repo's
   reviews stay expensive even capped; **Kodus + ML4 (E) if the POC (runbook 46) beats Copilot on cost per
   merged PR at equal findings quality.**

**Exit criterion, stated up front:** any alternative must catch what Copilot catches on this repo's own PRs
(repo-instruction adherence first — a reviewer that misses `AGENTS.md` rules costs more than it saves) at a
lower cost per merged PR. A cheaper reviewer that needs human correction every time loses at any price.

## What is not on the table

- **Swapping the model inside GitHub's own reviewer** — Copilot code review does not take BYO models; that
  path is BYOK in the IDE (runbook 44), not the PR reviewer.
- **Committed CI for the reviewer in this repo** — [ADR 32](../decisions/32-no-hosted-ci.md); option C runs
  ad hoc only.
- **Self-hosting a large model for review** — capped at ~32B-class by fleet hardware
  ([research 02](../research/02-llm-requirements.md), [research 08](../research/08-llm-server-hardware.md)).
