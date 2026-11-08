# Plan 02 — POC: Kodus (Kody) as the Code Review Service (K8s on `lab`, ML4 BYOK)

**Status**: 📋 Planned 2026‑11‑08 — **nothing executed yet; this is a plan, not a runbook.** Every
command and config value below is *unverified* until stage S1 runs; treat them as the intended shape,
and correct this doc with what actually happened. A runbook is authored only after a successful pass.
**Date**: 2026‑11‑08
**Idea**: [idea 18](../ideas/18-copilot-cr-cost-alternatives.md) (option E — the chosen POC) ·
tracked in [#190](https://github.com/jaroslaw-bagnicki/Homelab/issues/190)
**Analysis**: [research 54](../research/54-external-code-review-delegation.md) §3–§4
**Decisions**: [ADR 32](../decisions/32-no-hosted-ci.md) (not CI — an event-driven GitHub App, nothing
in Actions) · [ADR 15](../decisions/15-copilot-desktop-agentic.md) (secrets never in the repo —
[Security](../../AGENTS.md#security)) · [ADR 22](../decisions/22-k3s-arc-homelab.md) (k3s on `lab`)
· [ADR 24](../decisions/24-edge-ingress-appliance.md) (public ingress held)
**Related**: [runbook 44](../runbooks/44-copilot-mistral-byok.md) (Mistral Pro key, model IDs, $15/mo
shared allowance) · [#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179) ·
[kodustech/kodus-installer](https://github.com/kodustech/kodus-installer) · [docs.kodus.io](https://docs.kodus.io)

> ⚠️ **Verification status**: the installer layout, Helm chart path, env var names and webhook path
> below come from vendor docs/search (read 2026‑11‑08), **not** from a run. Expect drift; the POC's
> first task is to pin the real values here.

---

## Why this document

Copilot code review costs 2–3× the implementation work on some PRs since GitHub's 2026 usage-based
billing change ([research 54](../research/54-external-code-review-delegation.md) §1). Idea 18's
option E — **Kodus/Kody self-hosted, BYOK with `mistral-large-4`** — is the chosen POC because it is
the only option that is both a full review pipeline (webhook, Kody Rules, dashboard) and priced at
raw LLM tokens (~$0.05–0.30/review). This plan sequences the POC and names its exit gate: **an ADR on
Kodus adoption** (or a recorded rejection in research 54).

**Placement** (amended 2026‑11‑08): K8s on `lab` via the Helm path of `kodus-installer` — `cloudlab`
is being decommissioned and takes no new workloads. Docker Compose on `lab` is the fallback while the
k3s migration ([ADR 22](../decisions/22-k3s-arc-homelab.md)) is still held.

## Stages and gates

| Stage | Work | Exit gate |
|---|---|---|
| **S0 — Prerequisites** | k3s on `lab` up (or Compose fallback chosen); webhook ingress route decided (§3) | cluster reachable / fallback declared |
| **S1 — GitHub App + deploy** | §1 app, §2 Helm install, health checks | Kodus UI up on `lab`, app installed on the repo |
| **S2 — Webhook route** | §3 route + GitHub App "Ping" = 200 | GitHub delivers `pull_request` events |
| **S3 — POC run** | §4: 3–5 PRs, Kody vs manual Copilot, per-PR cost from Studio usage | measurement table complete |
| **S4 — Decision** | pass bar below → **ADR for Kodus adoption**; fail → record in research 54, retire idea 18 | ADR authored, or rejection recorded |

## Acceptance criteria (pass bar for S4)

| Criterion | How judged | Pass bar |
|---|---|---|
| **Cost per review** | Mistral Studio → Usage per PR (`cached_tokens` — $0.70 vs $0.07/M input) | ≪ Copilot's $0.25–5 AI-credits (+ Actions minutes on private repos) per review |
| **Findings that survive human review** | same PRs reviewed by Kody and by Copilot (manual request) | ≥ Copilot on this repo's PR shapes (docs, Ansible, Bicep, PowerShell) — esp. `AGENTS.md` adherence |
| **Latency** | PR open → review comment | minutes, not hours |
| **Hygiene** | no secrets in repo/logs; webhook signature verified | clean |

## S1 — GitHub App for Kody (separate from the Mistral app)

1. `github.com/settings/apps/new` (owner `jaroslaw-bagnicki`) — name e.g. `homelab-kodus-poc`.
2. **Webhook**: URL `https://kody.example.com/webhooks/github` (placeholder — real host from §3),
   secret generated now, events: `pull_request`, `issue_comment`, `pull_request_review_comment`.
3. **Permissions**: Metadata: read · Contents: read · **Pull requests: read/write** ·
   Issues: read/write (Kody comments on PRs and replies to threads).
4. Install **only on the `Homelab` repo**. Download the private key once.
5. Store App ID, private key and webhook secret as Kubernetes Secrets on `lab` (or AKV per ADR 15) —
   never in any git repo; `[REDACTED]` placeholders anywhere they'd be committed.

Deploy (intended shape — verify against the installer repo at run time):

```bash
git clone https://github.com/kodustech/kodus-installer.git && cd kodus-installer
# Helm chart under helm/ → namespace kodus on the lab k3s cluster.
# Secrets as Kubernetes Secrets (never in git): GITHUB_APP_ID, GITHUB_APP_PRIVATE_KEY,
#   GITHUB_WEBHOOK_SECRET (from S1), plus LLM BYOK: OpenAI-compatible base URL
#   https://api.mistral.ai/v1 · model mistral-large-4 · MISTRAL_API_KEY = the Pro-plan key
#   (runbook 44). Self-hosted infers the provider from the model name (kodustech/kodus-ai#1687) —
#   set the generic OpenAI-compatible fields explicitly.
helm upgrade --install kodus ./helm -n kodus --values values.yaml   # values.yaml stays out of git
```

First deploy: plan 15–30 min, then health checks per installer output. Stack = web UI, API, worker,
webhooks service, MCP manager + data stores.

## S2 — Route the webhook (open point)

GitHub must reach the webhook URL; public ingress is **held** ([ADR 24](../decisions/24-edge-ingress-appliance.md),
and the cloudflared tunnel still runs on the outgoing `cloudlab`). Options, in order of preference:

1. cloudflared/Caddy on `edge` (the designated ingress appliance) → `kody.example.com` → k3s
   Service/Ingress on `lab`; Cloudflare DNS record. Verify with the GitHub App "Ping" (200).
2. **Temporary**: the existing `cloudlab` tunnel until decommission — POC window only, no permanent
   workloads there.
3. LAN-only variant: skip the webhook, drive reviews from the Kodus UI/CLI on demand — measures model
   cost and quality, not the automated path.

## S3 — POC run

1. In the Kodus UI, connect the `Homelab` repo; enable automatic review on PRs.
2. On the repo, **disable automatic Copilot code review** (Settings → Copilot) for the POC window so
   reviews aren't double-billed; manual "request Copilot review" stays for the A/B.
3. Open 3–5 real PRs (or re-run recent ones); for each, also request a manual Copilot review.
4. Log per PR: model, wall-clock latency, Mistral usage (input/cached/output tokens → $), findings
   kept vs dismissed by the human reviewer, Copilot's findings on the same PR.

## S4 — Teardown / rollback (if rejected)

`helm uninstall kodus -n kodus` on `lab` (or `docker compose down` for the fallback), uninstall the
`homelab-kodus-poc` GitHub App (settings/installations), remove the tunnel route + DNS record,
re-enable Copilot auto review. AGPLv3 note: personal/homelab use is fine; if the service is ever
modified *and* served over a network, the modifications must be published.

## Caveats

- Billing: one Mistral Pro key funds Kody's ML4 calls; the $15/mo shared allowance is consumed first,
  then prepaid PAYG — same meter as [runbook 44](../runbooks/44-copilot-mistral-byok.md), so watch
  Studio usage before/after.
- Context window: runbook 44 measured an 800k window for ML4 in Vibe; check what Kody sends and log it.
- Kody Rules (custom conventions) are the lever for repo-instruction adherence — seed them from
  `AGENTS.md` highlights during S3.
- If the POC passes, promote to a proper Ansible workload (`ansible/workloads/kodus/`) + a
  `docs/workloads.md` row + an execution **runbook**; until then this plan is the whole record.
