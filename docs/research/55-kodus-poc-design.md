# 55 — Kodus (Kody) as a Self-Hosted Code-Review Service: POC Design and Evaluation Frame

**Source**: web research (Brave, read 2026‑11‑08) on kodus.io / docs.kodus.io /
`github.com/kodustech/kodus-installer` + `kodus-ai`, plus operator direction 2026‑11‑08 ("POC Kodus as
CR service"; "place it in K8s on `lab`, `cloudlab` is being decommissioned — no new workloads there";
"this is too small for a plan — keep it in research").

**Scope**: what Kodus/Kody is, why it is the chosen POC for [idea 18](../ideas/18-copilot-cr-cost-alternatives.md)
(option E, tracked in [#190](https://github.com/jaroslaw-bagnicki/Homelab/issues/190)), the intended
placement and its open questions, and the evaluation frame (what the POC must measure). Feeds
[research 54](54-external-code-review-delegation.md) §3–§4. Nothing here is an ADR; the adoption ADR is
a *POC output* if the pass bar is met.

**Status**: 📝 Analysis + proposed POC — **nothing executed yet**; installer layout, Helm values, env
names and webhook path below are vendor-doc claims, not run results. A runbook is authored only after a
successful pass.

---

## §1 What Kodus is (verified from vendor sources, 2026‑11‑08)

- **Kody** — open-source AI code review agent, AGPLv3 (`kodustech/kodus-ai`: NestJS API + Next.js
  dashboard + worker + webhooks service). Reviews PRs on GitHub, GitLab, Bitbucket, Azure DevOps,
  Forgejo with inline comments.
- **BYOK, zero markup** — 12 built-in providers plus generic OpenAI-compatible endpoints; you pay the
  model provider directly. `https://api.mistral.ai/v1` + `mistral-large-4` + the existing Pro key
  ([runbook 44](../runbooks/44-copilot-mistral-byok.md)) drops straight in. Self-hosted infers the
  provider from the model name (kodustech/kodus-ai#1687) — set the generic OpenAI-compatible fields
  explicitly.
- **Self-host** — `kodustech/kodus-installer`: clone, `cp .env.example .env`, run
  `./scripts/generate-secrets.sh`, then `./scripts/validate-env.sh`, then `./scripts/install.sh`
  (Compose); the installer exits if `.env` is absent and does not create it. A **Helm chart** is also
  included for k8s/OpenShift. All variable names come from `.env.example` — do not invent them; the
  self-hosted LLM config is the env-declared provider path (kodus-ai#1687, #2362), with Mistral as the
  OpenAI-compatible base URL, not a `MISTRAL_API_KEY`-style guess. Secrets (GitHub App ID/private
  key, webhook secret, LLM key) stay in your secret store, read at runtime. First deploy 15–30 min per
  vendor docs.
- **Depth** — hybrid AST + LLM to cut false positives, codebase context learned over time, custom
  **Kody Rules** (the lever for `AGENTS.md`-style adherence). Benchmarks: 63.4 F1 on Martian's Code
  Review Bench (Oct 2026, via cubic — vendor-adjacent source), vs Greptile 63.2 / CodeRabbit 61.8.
- **AGPLv3 caveat** — personal/homelab use fine; modify-and-serve over a network obliges publishing.

## §2 Why it is the chosen POC

Against idea 18's options: it is the only one that is both a **full review pipeline** (webhook → Kody
Rules → inline comments → dashboard) and priced at **raw LLM tokens** — ~$0.05–0.30 per review for ML4
at cache reuse ([research 54](54-external-code-review-delegation.md) §4), vs Copilot CR's $0.25–5 of AI
credits (+ Actions minutes on private repos) after the 2026 billing changes (§1 there).

## §3 Intended placement and open questions

- **Placement**: k3s on `lab` via the installer's Helm chart (namespace `kodus`), Secrets as
  Kubernetes Secrets (never in git — ADR 15 / repo Security). `cloudlab` takes **no new workloads**
  (decommission planned). Fallback while the k3s migration ([ADR 22](../decisions/22-k3s-arc-homelab.md))
  is still held: Docker Compose **on `lab`**.
- **Open question 1 — webhook ingress**: GitHub must reach the webhook URL (`…/github/webhook`); public
  ingress is held ([ADR 24](../decisions/24-edge-ingress-appliance.md)) and the cloudflared tunnel still
  runs on the outgoing `cloudlab`. **Network note**: the existing Caddy runs on `homelab_net`
  (runbook 16) while the Kodus Compose stack publishes the webhooks container on **host port 3332** on
  `kodus-backend-services` — a Caddy route alone gives no resolvable upstream. Attach Caddy to the
  Kodus network or route via the host port, and verify with the GitHub App "Ping" (200). Options:
  edge ingress once decided; temporary `cloudlab` tunnel for the POC window only; or a LAN-only variant
  (drive reviews from the Kodus UI/CLI — measures cost and quality, not the automated path).
- **Open question 2 — k3s dependency**: POC rides on the held ADR 22 workstream or uses the Compose
  fallback; decide when starting.
- **GitHub App for Kody** (separate from the Mistral app): `github.com/settings/apps/new`. Webhook URL
  path is **`/github/webhook`** (the webhooks service), not `/webhooks/github` — with the wrong path the
  install looks fine but Kody never receives events (kodus-ai#1856). Events: `pull_request`,
  `pull_request_review_comment`, `issue_comment`, **`push`**. Permissions: Metadata: read, Contents:
  read, **Pull requests: read/write**, Issues: read/write, **Checks: read/write** (kodus-ai#1923). Set
  the App's **callback URL and setup URL** to the Kodus web URL. Install only on the `Homelab` repo.
  Private key downloaded once, stored in K8s Secrets/AKV.

## §4 Evaluation frame (what the POC must produce)

1. Disable automatic Copilot CR on the repo for the POC window (manual Copilot requests stay for the
   A/B, so reviews aren't double-billed).
2. 3–5 real PRs; each reviewed by Kody automatically **and** by a manual Copilot review.
3. Per PR log: model, wall-clock latency, Mistral Studio usage (input/cached/output tokens → $),
   findings kept vs dismissed by the human reviewer, Copilot's findings on the same PR.

| Criterion | Pass bar |
|---|---|
| Cost per review | ≪ Copilot's $0.25–5 AI credits (+ runner minutes on private repos); watch `cached_tokens` ($0.70 vs $0.07/M input) |
| Findings that survive human review | ≥ Copilot on this repo's PR shapes (docs, Ansible, Bicep, PowerShell) — esp. `AGENTS.md` adherence via Kody Rules |
| Latency | minutes, not hours |
| Hygiene | no secrets in repo/logs; webhook signature verified |

**Outcome**: pass → author the Kodus adoption ADR (number on landing) + promote to
`ansible/workloads/kodus/` + runbook + `docs/workloads.md` row; fail → record the outcome in
[research 54](54-external-code-review-delegation.md) and retire [idea 18](../ideas/18-copilot-cr-cost-alternatives.md).

## §5 Sources (read 2026‑11‑08)

kodus.io (homepage, /pricing, /self-hosted-ai-code-review, /byo-llm-code-review) ·
docs.kodus.io (self-host guide, pricing deep dive) ·
github.com/kodustech/kodus-installer · github.com/kodustech/kodus-ai (incl. #1687 provider inference) ·
cubic.dev best-ai-code-review-tools (Martian bench F1) · operator direction 2026‑11‑08
