# Idea 16 — Evaluate Mistral Large 4 (Le Chonk) Against the Daily Driver

> Every doc, Ansible role, Bicep module and PowerShell script in this repo was written with an AI agent,
> and **one model — DeepSeek V4.1 Flash — is the daily driver for all of it**. That makes the model a
> *build dependency* of the whole project, yet no document here records why it is that model or what
> would displace it. Mistral Large 4 is close enough on price and stronger on paper in a few dimensions to
> justify a **bounded comparison**, not a migration.

**Status**: 🧠 Idea — no account, no spend, nothing reconfigured
**Date**: 2026-11-06
**Sources**: [Mistral pricing](https://mistral.ai/pricing/) · [Mistral Large 4 model card](https://docs.mistral.ai/models/mistral-large-4-0) · [DeepSeek V4.1 Flash 1017 model card](https://docs.mistral.ai/models/deepseek-v4-flash-1017) — all read 2026-11-06
**Related**: [ADR 15](../decisions/15-copilot-desktop-agentic.md) (Copilot BYOK provider) · [ADR 17](../decisions/17-adopt-opencode.md) (OpenCode, DeepSeek API + MiniMax plan) · [research 19](../research/19-copilot-desktop-agentic.md) · [docs/opencode-customization](../opencode-customization/README.md) (per-instance LLM key) · [research 02](../research/02-llm-requirements.md) / [research 08](../research/08-llm-server-hardware.md) (why local inference is out of scope)

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
| Released | 2026-10-06, GA | 2026-10-28, public preview on Mistral's platform |
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

- The daily driver becomes the **experimental control on the same host** — no cross-vendor latency or
  quota differences muddying the result.
- `opencode.json` already takes providers by name; a `mistral` provider is one block, and
  [ADR 15](../decisions/15-copilot-desktop-agentic.md)'s BYOK path (ADR 15) is an OpenAI-compatible base
  URL plus a key — the same shape as the existing `https://api.deepseek.com/v1` entry.
- The Cloudlab OpenCode instances already carry a **per-instance LLM key** layer
  ([opencode-customization](../opencode-customization/README.md)), so the winner can be rolled out per
  project rather than fleet-wide.

One caveat that must not be glossed over: on Mistral's platform, DeepSeek V4.1 Flash is marked
**public preview**, whereas the current setup calls DeepSeek's own API directly. The A/B is a clean
*model* comparison but not a clean *vendor* comparison — a preview endpoint is the wrong thing to put
daily work on.

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

## Risks and honest doubts

- **Churn is the norm, not the exception.** Both models are weeks old (`v26.10`, `1017` date-stamped). Any
  preference is a snapshot of a moving target — which argues for a *cheap, repeatable* test rather than a
  one-off verdict, and argues against rewriting anything around a winner.
- **A preference without a written outcome is worthless.** If the experiment runs and nothing is recorded,
  the repo is back to "it works" as the only evidence — the same position this idea exists to fix.
- **Consumer plans are not the comparison.** Mistral's subscription tiers have message and usage caps and
  are aimed at the Vibe product; the only figure that transfers to agentic work is the metered API price.
  ([ADR 15](../decisions/15-copilot-desktop-agentic.md)'s reasoning for BYOK over subscription applies
  unchanged.)
- **Vendor fit is a real but unproven criterion.** An EU vendor with an open-weight licence is a plausible
  advantage if this ever stops being a hobby — data residency, procurement, licence portability. It is a
  *criterion to weigh*, not a conclusion to assume, and it does not outweigh instruction adherence.

## Recommendation

**Capture the idea and run a bounded evaluation — do not migrate, and do not adopt on paper.** The cost
case does not exist; only the quality case can decide this, and the quality case needs evidence from this
repo's own tasks.

Sequence, with an exit at every step:

1. **Zero-config sanity check** — free tier in Mistral Studio, two real tasks from this repo (an ADR and an
   Ansible role). If it visibly mishandles the instruction files, stop here and mark this idea 🪦 Retired.
2. **One week, side by side** — `mistral-large-4` as a *second* provider in `opencode.json`, DeepSeek left
   untouched as the control. Same work, both models, log which one produced a task that survived review.
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
