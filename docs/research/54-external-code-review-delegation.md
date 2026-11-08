# 54 — Delegating GitHub Code Review to External Services: the June 2026 Copilot Billing Change and the Alternatives

**Source**: web research (Brave search, 2026‑11‑08) — GitHub Blog announcements and changelogs, GitHub Docs,
GitHub Community discussions, vendor pricing pages and 2026 comparison articles (full list in §7). Trigger:
operator observation, 2026‑11‑08: after GitHub changed how Copilot code review is billed, some pull-request
reviews on his repos cost **2–3× the implementation work itself** — unacceptable, so he wants alternatives.

**Scope**: why Copilot code review got expensive in 2026 (the billing mechanics, not a rant), the four ways to
delegate PR review outside GitHub's own reviewer, the third-party bot landscape with 2026 pricing, the
BYO-model/self-hosted path (where Mistral Large 4 / Vibe fit), and the security/privacy surface of each.
Feeds [idea 18](../ideas/18-copilot-cr-cost-alternatives.md). Nothing here is an ADR.

**Status**: 📝 Analysis — no decision taken yet.

---

## §1 — Why Copilot code review got expensive: the 2026 billing mechanics

Three changes stacked on top of each other:

1. **2026‑06‑01 — premium requests out, AI Credits in.** All Copilot plans moved from Premium Request Units
   (PRUs) to usage-based billing in **GitHub AI Credits** (1 credit = **$0.01**), metered **per token** —
   input, output *and cached* — at per-model rates ([GitHub Blog, "GitHub Copilot is moving to usage-based
   billing"](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/),
   [changelog 2026‑06‑01](https://github.blog/changelog/2026-06-01-updates-to-github-copilot-billing-and-plans/)).
   Plans include a monthly credit allotment (e.g. Business 3,000 credits/user/month during the initial window);
   overage is billable, and a spending limit can hard-stop it. Community pushback is documented in
   [discussion #192948](https://github.com/orgs/community/discussions/192948) and
   [#192963](https://github.com/orgs/community/discussions/192963).
2. **2026‑06‑01 — code review bills twice on private repos.** Every Copilot code review additionally consumes
   **GitHub Actions minutes** for the GitHub-hosted runner the review agent runs on, separate from the AI
   credits — "you pay twice" ([changelog](https://github.blog/changelog/2026-06-01-updates-to-github-copilot-billing-and-plans/),
   [Tenki](https://tenki.cloud/blog/copilot-code-review-actions-minutes-cost),
   [Codacy](https://blog.codacy.com/github-copilot-code-review-used-to-be-included-from-june-1st-you-pay-twice)).
   **Public repositories keep Actions minutes free** — only the AI credits apply there. Org admins can set a
   default (possibly self-hosted or larger) runner for all repos since June 2026.
3. **2026‑08‑28 / 2026‑11‑06 — the default review became a multi-model council.** The default effort level
   became **Balanced** for all repos ([changelog 2026‑10‑02](https://github.blog/changelog/2026-10-02-copilot-code-review-api-support-and-new-default-effort-level/)),
   and from **2026‑11‑06** Balanced reviews run **three separate reviewer models, plus a fourth model combining
   their findings** ([changelog 2026‑11‑06](https://github.blog/changelog/2026-11-06-copilot-code-review-api-management-and-review-overview-updates/)).
   Four model passes over the same diff, each metered per token, is the multiplier that turns token-based billing
   into "2–3× the implementation cost" on large PRs.

**What one review costs now.** GitHub's own estimate: **$0.25–$5 of AI credits per review at the default
effort** ([cubic](https://www.cubic.dev/blog/github-copilot-code-review)); on private repos add Actions
minutes for the runner time. The spread is driven by diff size and how much repo context the council pulls in —
the exact profile of agent-generated PRs in this repo. Mitigations that exist *inside* Copilot: lower effort
level per repo, disable automatic reviews (Settings → Copilot), per-repo API management
(REST/GraphQL, since 2026‑11‑06), AI-credit spending limits, and the new "addressed rate" metric.

## §2 — The four delegation patterns

| Pattern | How it works | Model choice | Code leaves GitHub? | Cost shape |
|---|---|---|---|---|
| **1. First-party: Copilot code review** | Assign `copilot-pull-request-reviewer[bot]` via REST API, or automatic review via rulesets; posts inline comments | fixed (GitHub's models) — **not swappable** | no | AI credits (+ Actions minutes on private repos), per token |
| **2. Third-party GitHub App** (Marketplace) | App install with `contents:read`, `pull-requests:read/write`, webhook on PR events; vendor indexes the repo and posts reviews | vendor's | **yes — vendor's cloud** | flat per-seat, or per-review credits; free OSS tiers common |
| **3. BYO-model in Actions / webhook** | Your workflow fetches the diff, calls any OpenAI-compatible LLM endpoint, posts comments | **yours** (Mistral, DeepSeek, local) | only to the LLM endpoint you choose (or nowhere, if local) | per-token API + runner minutes |
| **4. Local agent, ad hoc** | Vibe / OpenCode on the workstation pulls the PR (`gh pr diff` / GitHub MCP), reviews, optionally posts comments | **yours** | only to your LLM provider | per-token API only |

Pattern 1 cannot use Mistral. Patterns 3–4 are the only ones where **Mistral Large 4 / Vibe** plug in — and
pattern 3 is where `appleboy/LLM-action` fits: it speaks any OpenAI-compatible endpoint, so
`https://api.mistral.ai/v1` with `mistral-large-4` drops straight in (also `NOAA-EMC/ci-llm-code-review`,
Kodus self-hosted AGPLv3, or a webhook receiver → local Ollama/vLLM for zero cloud egress).

## §3 — Third-party bot landscape, 2026 pricing

Comparison articles are vendor-influenced (several vendors each claim #1 on some benchmark — read them
accordingly); the consistent split from 2026 round-ups
([Sourcegraph](https://sourcegraph.com/blog/automated-code-review-tools),
[Levelop](https://levelop.dev/blog/best-ai-code-review-tools-2026-coderabbit-greptile-qodo-compared),
[tech-insider](https://tech-insider.org/coderabbit-vs-greptile-vs-qodo-2026/)):

| Tool | Strength | Indicative price (2026) |
|---|---|---|
| **CodeRabbit** | lowest noise, PR walkthroughs, learns from past reviews; free forever for OSS | Lite ~$12, Pro ~$24/user/mo annual |
| **Greptile** | deepest whole-codebase indexing, highest raw catch rate; strictness setting | ~$30/seat/mo, 50 reviews included; free Starter ~50 credits/mo, 1 dev |
| **Qodo** (ex-Codium, built on OSS PR-Agent) | policy enforcement, IDE coverage, deployment flexibility | Teams ~$30/user/mo |
| **Graphite Agent** | stacked-PR workflows | Starter ~$20, Team ~$40 |
| Cursor Bugbot, Gitar, Codacy, SonarQube Cloud, Macroscope | niche fits (bug-focused, auto-fix, static analysis, enterprise) | $10–40+/user/mo |

Flat per-seat pricing is the direct answer to "review cost scales with PR size": a $24/seat bot costs the
same on a 10-line and a 2,000-line PR.

## §4 — The BYO-model path: what a Mistral Large 4 review actually costs

Rough math for this repo's PR profile (a docs/Ansible PR: diff ~10–50k tokens + pulled repo context
~100–300k tokens, mostly cached on repeat turns):

- `mistral-large-4` at **$0.70/M input, $0.07/M cached, $2.10/M output** (idea 16 price sheet) → a review with
  heavy cache reuse lands around **$0.05–0.30**; at 0 % cache ~$0.30–1.00. Against Copilot's $0.25–$5 per
  review (plus runner minutes on private repos), that is the 2–3×+ gap in the other direction.
- `deepseek-v4-1-flash-1017` (the daily driver, idea 16) is ~2.3× cheaper still on input.
- A **local** model (Ollama/vLLM on the lab hardware) is ~zero marginal cost but capped at ~32B-class by the
  fleet ([research 02](02-llm-requirements.md), [research 08](08-llm-server-hardware.md)) — fine for a second
  pair of eyes, not for repo-instruction-heavy review.

## §5 — Security and privacy surface

- **Pattern 2 apps get read access to your code** — it leaves GitHub to the vendor. Check each vendor's
  privacy page, retention and SOC 2 before installing; for sensitive repos prefer pattern 3/4 or self-hosted
  (Kodus AGPLv3 keeps keys in your secret store).
- **Actions safety**: trigger the reviewer workflow on `pull_request`, **never `pull_request_target` with
  fork PRs** (classic pwn-request secret exfiltration —
  [GitHub Security Lab](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/),
  [secure-use docs](https://docs.github.com/en/actions/security-for-github-actions/secure-use-reference));
  LLM API keys belong in Actions secrets, never in the workflow file.
- **Copilot itself**: code review can pull context from configured MCP servers; repo admins can manage effort
  and policies via the new REST/GraphQL APIs (2026‑11‑06).

## §6 — Fit with this repo

- This repo is **public**, so pattern 1 here pays AI credits only (no Actions minutes) — but the user's 2–3×
  observation is on his repos generally, including private ones.
- [ADR 32](32-no-hosted-ci.md) deliberately keeps hosted CI out of this repo, and PRs here are
  **human-reviewed in the GitHub UI** — so a pattern-3 workflow would run *ad hoc* (locally / on demand), not
  as committed CI. Pattern 4 (Vibe + native Le Chonk, per [runbook 44](../runbooks/44-copilot-mistral-byok.md))
  is the zero-infrastructure version and already works. ML4 also answers in **VS Code/Copilot chat** since
  2026-11-08 via the Responses API BYOK path (`apiType: "responses"`, `/v1/responses`) — it bypasses the
  vscode#338309 chat-completions parser bug, which still blocks ML4 on the `chat-completions` BYOK path
  ([#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179)#issuecomment-6719695584).
- The model question is already framed by [idea 16](../ideas/16-ai-model-mistral-large-4.md) and #179: one
  Mistral Pro key serves `mistral-large-4` and the DeepSeek control, so a reviewer A/B reuses the same
  allowance and method (task success per attempt, cost per completed task).

## §7 — Sources (all read 2026‑11‑08)

- [GitHub Blog — Copilot moving to usage-based billing](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/) · [changelog 2026‑06‑01 billing/plans](https://github.blog/changelog/2026-06-01-updates-to-github-copilot-billing-and-plans/) · [changelog 2026‑10‑02 default Balanced effort](https://github.blog/changelog/2026-10-02-copilot-code-review-api-support-and-new-default-effort-level/) · [changelog 2026‑11‑06 three reviewer models + combiner](https://github.blog/changelog/2026-11-06-copilot-code-review-api-management-and-review-overview-updates/) · [GitHub Docs — Copilot code review](https://docs.github.com/en/copilot/concepts/agents/code-review) · Community discussions [#192948](https://github.com/orgs/community/discussions/192948), [#192963](https://github.com/orgs/community/discussions/192963)
- Cost analyses: [cubic — what a review costs](https://www.cubic.dev/blog/github-copilot-code-review) ($0.25–$5/review estimate) · [Tenki — AI credits + Actions minutes](https://tenki.cloud/blog/copilot-code-review-actions-minutes-cost) · [Codacy — "you pay twice"](https://blog.codacy.com/github-copilot-code-review-used-to-be-included-from-june-1st-you-pay-twice) · [repowise — cost per 100 PRs](https://repowise.dev/blog/comparisons/ai-code-review-pricing-compared)
- Tool comparisons/pricing: [Sourcegraph — 13 tools compared](https://sourcegraph.com/blog/automated-code-review-tools) · [Levelop — Greptile/CodeRabbit/Qodo 2026](https://levelop.dev/blog/best-ai-code-review-tools-2026-coderabbit-greptile-qodo-compared) ($24/$30/$30 per seat) · [tech-insider — $12 Lite to $30+ seats](https://tech-insider.org/coderabbit-vs-greptile-vs-qodo-2026/) · [Mastra — 6 tools](https://mastra.ai/articles/ai-code-review-tools) · [CodeRabbit pricing/FAQ/privacy](https://www.coderabbit.ai/pricing)
- BYO-model/self-hosted: [appleboy/LLM-action](https://github.com/appleboy/LLM-action) (OpenAI-compatible endpoints incl. Mistral) · [NOAA-EMC/ci-llm-code-review](https://github.com/NOAA-EMC/ci-llm-code-review) · [Kodus self-hosted](https://kodus.io/self-hosted-ai-code-review/) · [SitePoint — local LLM review architecture](https://www.sitepoint.com/self-hosting-ai-code-review-local-models/) · [PromptQuorum — local LLM in Actions](https://www.promptquorum.com/power-local-llm/local-llm-code-review-ci-cd)
- Security: [Security Lab — pwn-requests](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/) · [GitHub Actions secure-use reference](https://docs.github.com/en/actions/security-for-github-actions/secure-use-reference)
