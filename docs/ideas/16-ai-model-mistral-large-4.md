# Idea 16 — Evaluate Mistral Large 4 (Le Chonk) Against the Daily Driver

> Every doc, Ansible role, Bicep module and PowerShell script in this repo was written with an AI agent,
> and **one model — DeepSeek V4.1 Flash — is the daily driver for all of it**. That makes the model a
> *build dependency* of the whole project, yet no document here records why it is that model or what
> would displace it. Mistral Large 4 is close enough on price and stronger on paper in a few dimensions to
> justify a **bounded comparison**, not a migration.

**Status**: 🪦 Retired — **outcome recorded 2026-11-14** (Outcome section below, tracked in [#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179)): use both on one Mistral Pro account — DeepSeek V4.1 Flash stays the daily driver served via Mistral (the DS direct subscription is retired), Mistral Large 4 grows via Mistral Vibe; the provider note in ADR 15/17 is superseded by this outcome  
**Date**: 2026-11-06  
**Sources**: [Mistral pricing](https://mistral.ai/pricing/) · [Mistral Large 4 model card](https://docs.mistral.ai/models/mistral-large-4-0) · [DeepSeek V4.1 Flash 1017 model card](https://docs.mistral.ai/models/deepseek-v4-flash-1017) · [Subscriptions / included usage](https://docs.mistral.ai/admin/billing-usage/subscriptions) · [Vibe CLI configuration](https://docs.mistral.ai/vibe/code/cli/configuration) — all read 2026-11-06  
**Related**: [ADR 15](../decisions/15-copilot-desktop-agentic.md) (Copilot BYOK provider) · [runbook 44](../runbooks/44-copilot-mistral-byok.md) (Mistral BYOK in Copilot/VS Code for the A/B) · [ADR 17](../decisions/17-adopt-opencode.md) (OpenCode, DeepSeek API + MiniMax plan) · [research 19](../research/19-copilot-desktop-agentic.md) · [docs/opencode-customization](../opencode-customization/README.md) (per-instance LLM key) · [research 02](../research/02-llm-requirements.md) / [research 08](../research/08-llm-server-hardware.md) (why local inference is out of scope)

---

## Context

The lab's AI stack is deliberately thin — a CLI agent on a subscription plan, a paid API behind it for
cost control ([ADR 15](../decisions/15-copilot-desktop-agentic.md), [ADR 17](../decisions/17-adopt-opencode.md)),
and `opencode.json` declaring exactly two providers: DeepSeek and the MiniMax coding plan. DeepSeek V4.1
Flash does the work; MiniMax is a second key, not a tested substitute.

That is a **single point of dependency** on four axes at once — price, availability, deprecation and
quality drift — and the repo currently absorbs it silently. Everything is undated: no measurement says
the daily model is the right one, so "it works" is the only evidence, and "it stopped working well" would
be noticed late and informally.

The specific trigger for writing this down: Mistral Large 4 (v26.10, released 2026-10-06 — codename
**Le Chonk**, after the model card's asset) is advertised with the same 1M context and a comparable
per-token price. It is worth asking the boring question — *is the model we build everything with still
the best fit?* — before something forces the question instead.

## The two models, side by side

| | **Mistral Large 4** (`mistral-large-4`, v26.10) | **DeepSeek V4.1 Flash 1017** (`deepseek-v4-1-flash-1017`) |
|---|---|---|
| Released | 2026-10-06, **GA** badge on the card | 2026-10-28, **public preview** + third-party badges on the card |
| Licence | Mistral Ecosystem Open Weight Licence | MIT |
| Shape | MoE, **52B active / 1.05T total**, 1.6B vision encoder | not published on the card |
| Context | **1M** | **1M**, max output 128k |
| Modalities | text + image | text + image |
| Input | **$0.70 /M** | **$0.30 /M** |
| Cached input | **$0.07 /M** | **$0.007 /M** |
| Output | **$2.10 /M** | **$1.20 /M** |
| Relative cost | **2.3× input · 1.75× output · 10× cached** | baseline |

Headline reading: **Mistral Large 4 is not cheaper.** DeepSeek V4.1 Flash wins on every line of the price
sheet, by 1.75× at best and 10× on cached input — and cached input is what dominates a long agentic
session, where the same instruction files and file bodies are re-read every turn. So a swap cannot be
justified on cost. It can only be justified if the bigger, newer model produces measurably better work
per unit of *completed task*, which is a different number from tokens.

## What makes this cheap to test

The decisive structural fact: **DeepSeek V4.1 Flash is itself served by Mistral's platform** —
"a third-party open weight model from DeepSeek, hosted by Mistral … served without Mistral
modifications". One Mistral Studio key therefore reaches **both** models over the same
OpenAI-compatible endpoint.

That turns the comparison from a project into a config edit:

- The daily driver becomes the **experimental control on the same host** — no cross-vendor routing or
  billing differences muddying the result. Latency and throttling are *measured*, not assumed equal: two
  models behind one endpoint can still sit on different capacity.
- `opencode.json` already takes providers by name; a `mistral` provider is one block, and
  [ADR 15](../decisions/15-copilot-desktop-agentic.md)'s BYOK path (ADR 15) is an OpenAI-compatible base
  URL plus a key — the same shape as the existing `https://api.deepseek.com/v1` entry.
- The Cloudlab OpenCode instances already carry a **per-instance LLM key** layer
  ([opencode-customization](../opencode-customization/README.md)), so the winner can be rolled out per
  project rather than fleet-wide.

### Where the A/B bills

Checked because "do I need a separate DeepSeek account to keep the control?" decides whether step 2 is
one key or two:

- **Plans are global, not per-surface.** "Mistral plans are global: the same plan applies across Vibe,
  Studio, and API usage", and the plan's **included monthly usage is shared across Studio, API and Vibe
  Code** — it is consumed first, then prepaid pay-as-you-go credits take over. Pro carries **$15 /mo** of
  included usage.
- **No documented plan tier gates third-party models.** They are metered API models like any other, billed
  from the same allowance — so the A/B is one Mistral account either way.
- **But the catalogue is not the price sheet.** Vibe's documented chat-capable model list includes
  **Z.ai GLM 5.3 / 5.2** as its third-party entries — **`DeepSeek V4.1 Flash 1017` is not listed**, and
  Mistral Large 4 is not either (the table still shows `mistral-large-latest` = Large 3). `/model` lists
  only models *configured for the account*, so this is a "verify in the account", not a "read the docs".
- **Not a blocker for this repo:** the daily agent is `opencode` + Copilot BYOK
  ([ADR 15](../decisions/15-copilot-desktop-agentic.md)), both plain OpenAI-compatible API clients — the
  Vibe catalogue never enters the picture. Adding a model is a `[[models]]` preset with
  `provider = "mistral"` and the model ID as `name`; Vibe needs `max_context_length` set for a model it
  does not know.
- **Stale number to ignore:** the pricing FAQ quotes "Mistral Large costs $0.5/M in and $1.5/M out" while
  the [Large 4 model card](https://docs.mistral.ai/models/mistral-large-4-0) states $0.70 / $2.10. The
  per-model card is authoritative; the FAQ is generic and lags the release.

One caveat that must not be glossed over: on Mistral's platform, DeepSeek V4.1 Flash is marked
**public preview**, whereas the current setup calls DeepSeek's own API directly. The A/B is a clean
*model* comparison but not a clean *vendor* comparison — a preview endpoint is the wrong thing to put
daily work on.

## Decision — 2026-11-06: run the evaluation, not the migration

**Decided: run the comparison on a Mistral Pro subscription, with both models served through it.** Not
Vibe's chat window, not a second vendor account — the metered API that `opencode` and Copilot BYOK already
speak, funded from one allowance.

- **Both sides of the A/B come from one provider.** `mistral-large-4` is the candidate;
  `deepseek-v4-1-flash-1017` is the control on the same host, so *routing* is constant — but latency and
  throttling remain outcomes to measure, since two models behind one endpoint can sit on different
  capacity.
- **Two prerequisites before step 2, both checked in the account rather than the docs:** both model IDs
  must be usable for the organization (the Vibe catalogue omits DeepSeek and still shows Large 3), and
  overage needs pay-as-you-go **enabled with prepaid credits** — included usage alone will not carry a
  week of agentic work.
- **The Pro plan is the funding vehicle, not the surface.** Its **$15 /mo** of included usage is shared
  across Studio, API and Vibe Code, and pay-as-you-go credits extend it, so the test needs no second
  billing relationship.
- **The daily driver does not move yet.** Real work stays on DeepSeek's own API
  ([runbook 13 §2](../runbooks/13-copilot-desktop-setup.md)); the Mistral-served DeepSeek is a *test*
  control, because it is public preview there.
- **No ADR yet.** This decides *how to find out*, not *what the model is* — the ADR lands only if Large 4
  wins (step 3 below), which is the "decide in writing" the idea was missing.

**Budget reality check.** $15 is a test budget, not a month of agentic coding, and **cache hit rate decides
which number applies**: a session with ~1M input and ~100k output costs **$0.91 on Large 4 at 0 % cache
hits but $0.28 at 100 %** — against **$0.42 and $0.13** on V4.1 Flash. So $15 covers roughly **16–53**
Large 4 sessions or **35–116** DeepSeek ones. Expect a pay-as-you-go top-up, and run step 1 in the
Playground — no config needed, but it draws on the same shared allowance, so it is cheap rather than free.

## What is not on the table

**Self-hosting.** Mistral Large 4 is open-weight, but at **1.05T total parameters** it is several orders
of magnitude past anything the fleet can hold — [research 02](../research/02-llm-requirements.md) and
[research 08](../research/08-llm-server-hardware.md) already established that even a 32B-class model is
the ceiling for local inference here. Open weight buys licence terms and the option of another host
later; it buys **no** local inference, no offline capability, and no privacy story beyond "the vendor
allows it".

## What would actually be measured

Not a benchmark table — this repo's own work, because the failure mode that matters is not "answers a
question well" but "**follows 400 lines of `AGENTS.md` and `copilot-instructions.md` without being
nagged**".

| Axis | How it is judged | Why it dominates |
|---|---|---|
| **Instruction adherence** | does it obey the repo's rules (branch workflow, changelog bar, ADR format, no `(type)` in PR titles) first time | the repo *is* its instructions; a model that ignores them costs more than it saves |
| **Tool-call fidelity** | GitHub MCP, Azure MCP, file edits, `ansible-lint` loops | agentic coding here is mostly tool orchestration |
| **Task success without a retry** | completed task per attempt, on a fixed set of 4 task types the repo actually produces: Ansible role edit, ADR/research authoring, Bicep module, PowerShell script | retries are where the token bill and the frustration live |
| **Cost per completed task** | Studio usage report ÷ tasks completed | separates "cheaper tokens" from "cheaper outcome" |
| **Wall clock** | time to a finished, passing task | the actual daily cost |

**Method, fixed before the first run:** four tasks with identical prompts and identical starting commits;
acceptance is the repo's own gates (lint, review, changelog bar) — a task passes only if it needs no
correction — and **retries are counted per task**, so a model that needs three attempts is recorded as
three, not as one expensive success.

## Risks and honest doubts

- **Churn is the norm, not the exception.** Both models are weeks old (`v26.10`, `1017` date-stamped). Any
  preference is a snapshot of a moving target — which argues for a *cheap, repeatable* test rather than a
  one-off verdict, and argues against rewriting anything around a winner.
- **A preference without a written outcome is worthless.** If the experiment runs and nothing is recorded,
  the repo is back to "it works" as the only evidence — the same position this idea exists to fix.
- **A subscription is a bundle, not a price.** Pro's included usage is metered in dollars and shared across
  surfaces, so it works as a prepaid runway — but the figure that decides anything is still the per-token
  API price, and $15 is a *test* budget, not a permanent one
  ([ADR 15](../decisions/15-copilot-desktop-agentic.md)'s argument for BYOK over subscription stands).
- **Vendor fit is a real but unproven criterion.** An EU vendor with an open-weight licence is a plausible
  advantage if this ever stops being a hobby — data residency, procurement, licence portability. It is a
  *criterion to weigh*, not a conclusion to assume, and it does not outweigh instruction adherence.

## Recommendation

**Capture the idea and run a bounded evaluation — do not migrate, and do not adopt on paper.** The cost
case does not exist; only the quality case can decide this, and the quality case needs evidence from this
repo's own tasks.

Sequence, with an exit at every step:

1. **Playground first, not the agent** — two real tasks from this repo (an ADR and an Ansible role) in
   Studio's Playground, which needs no config and no container. It still draws on the shared allowance,
   so this is a cheap check rather than a free one. If Large 4 visibly mishandles the instruction files,
   stop here, mark this idea 🪦 Retired, and the remaining $15 rolls to the next month.
2. **One week, side by side, on the Pro key** — `mistral-large-4` and `deepseek-v4-1-flash-1017` as two
   model presets under one `mistral` provider in `opencode.json`; the DeepSeek-direct provider stays
   configured and untouched for real work. Log per task which model produced something that survived
   review, and read the Studio usage report before and after.
3. **Decide in writing** — if Large 4 wins on task success and adherence, author the ADR that records the
   daily model (superseding the model note in [ADR 15](../decisions/15-copilot-desktop-agentic.md) /
   [ADR 17](../decisions/17-adopt-opencode.md)). If it loses, record that outcome *in this doc* and retire
   it. Either way the repo stops being silent about its build dependency.

**Exit criterion, stated up front:** a model that does not follow `copilot-instructions.md` / `AGENTS.md`
deterministically loses at any price — the 2.3× input premium buys nothing if the agent still needs
correction every third turn.

**Possible outcomes** (all legitimate): DeepSeek stays sole daily driver; DeepSeek stays daily with Mistral
as a genuine fallback provider; Mistral Large 4 takes over the heavy tasks (ADR/research authoring) while a
cheaper model handles mechanical edits — the split being the most likely landing point, since cost and
capability rarely move together.

## Outcome — 2026-11-14: use both, on one Mistral billing account

**Decided by the owner and recorded here per step 3, tracked in [#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179).**
The split lands where "Possible outcomes" predicted — cost and capability do not move together.

- **DeepSeek V4.1 Flash remains the daily driver — now served through Mistral** as
  `deepseek-v4-1-flash-1017` on `https://api.mistral.ai/v1`, so its usage bills under the same **Mistral
  Pro** subscription. The **DeepSeek direct subscription is retired**: the BYOK entry for it
  ([runbook 13 §2](../runbooks/13-copilot-desktop-setup.md)) is replaced by the Mistral one
  ([runbook 44](../runbooks/44-copilot-mistral-byok.md)), and the `deepseek` provider in `opencode.json`
  gives way to the `mistral` provider with both model presets. This supersedes the *provider* note in
  [ADR 15](../decisions/15-copilot-desktop-agentic.md) / [ADR 17](../decisions/17-adopt-opencode.md); the
  *model* does not change. Mistral Large 4's price — 2.3× input, 1.75× output, 10× cached input, and in
  practice quite expensive on agentic sessions — still rules it out as the everyday model.
- **The preview badge is accepted, with a fallback.** On Mistral's platform the DeepSeek card is badged
  **public preview** + third-party — the reason the 2026-11-06 decision kept daily work on DeepSeek's own
  API. The owner accepts the preview endpoint for one billing relationship; if it degrades, re-enable the
  DeepSeek direct key.
- **Mistral Large 4 is adopted alongside for the heavy tasks** — long, reasoning-heavy authoring —
  especially through **Mistral Vibe**, whose sessions bill as `mistral-large-4-0` on the same account, and
  through Copilot/VS Code BYOK per [runbook 44](../runbooks/44-copilot-mistral-byok.md). Hands-on, its
  reasoning reads smoother than V4.1 Flash's on exactly those tasks.
- **One billing relationship carries everything.** The Pro plan's $15/mo included usage is shared
  across Studio, API and Vibe Code, so the daily driver, ML4 heavy tasks and any future A/B all meter on
  one key with one usage report.

**Evidence, honestly stated:** the formal four-task side-by-side (step 2) did not run. The decision rests
on the probes recorded on #179 (2026-11-07/08 — both models reachable on one Pro key, cached and reasoning
tokens metered, the VS Code chat path working over the Responses API) plus hands-on use since. The fixed
method above stays as the re-check if the split is ever revisited; both models are date-stamped and move.
