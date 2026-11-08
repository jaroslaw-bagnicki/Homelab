# POC: Kodus (Kody) as the Code Review Service — self-hosted on `cloudlab`, ML4 BYOK

> Idea: [idea 18](../ideas/18-copilot-cr-cost-alternatives.md) — Copilot CR costs 2–3× implementation on
> some PRs since the 2026 usage-based billing change; POC the BYO-model pattern with **Kodus/Kody**
> ([research 54](../research/54-external-code-review-delegation.md) §3–§4). Not CI: an event-driven
> GitHub App + self-hosted service, so [ADR 32](../decisions/32-no-hosted-ci.md) is not touched —
> nothing lands in GitHub Actions.
> Secrets pattern: [ADR 15](../decisions/15-copilot-desktop-agentic.md) — keys in the secret store /
> environment, **never in the repo** ([Security](../../AGENTS.md#security)).
> Related: [runbook 44](44-copilot-mistral-byok.md) (Mistral Pro key, both model IDs, $15/mo shared
> allowance) · [#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179) ·
> [Kodus installer](https://github.com/kodustech/kodus-installer) · [Kodus docs](https://docs.kodus.io)

**Status**: 📋 POC planned 2026‑11‑08 — not deployed yet.
**Placement**: `cloudlab` (Contabo VPS, where the other Docker services already run — runbook 16),
behind the existing Caddy/cloudflared public route, because GitHub must reach the webhook URL.
The Homelab repo is **public**, so no code-sensitivity issue with a cloud VPS; self-hosting still keeps
the review pipeline (and the LLM key usage) under our control.

---

## §0 Goal and acceptance criteria

Run Kody as the PR reviewer on `jaroslaw-bagnicki/Homelab` for a bounded POC, model
`mistral-large-4` via the existing Mistral Pro key, and decide against Copilot CR:

| Criterion | How judged | Pass bar |
|---|---|---|
| **Cost per review** | Mistral Studio → Usage per PR (watch `cached_tokens` — $0.70 vs $0.07/M input) | ≪ Copilot's $0.25–5 AI-credits (+Actions minutes on private repos) per review |
| **Findings that survive human review** | same PRs reviewed by Kody and by Copilot (manual request) | ≥ Copilot on this repo's PR shapes (docs, Ansible, Bicep, PowerShell) — esp. `AGENTS.md` adherence |
| **Latency** | time from PR open to review comment | minutes, not hours |
| **Hygiene** | no secrets in repo/logs; webhook signature verified | clean |

## §1 GitHub App for Kody (separate from the Mistral app)

1. `github.com/settings/apps/new` (owner `jaroslaw-bagnicki`) — name e.g. `homelab-kodus-poc`.
2. **Webhook**: URL `https://kody.example.com/webhooks/github` (placeholder — real host is the
   cloudlab tunnel route, §4), secret generated now, events: `pull_request`, `issue_comment`,
   `pull_request_review_comment`.
3. **Permissions**: Metadata: read · Contents: read · **Pull requests: read/write** ·
   Issues: read/write (Kody comments on PRs and replies to threads).
4. Install **only on the `Homelab` repo**. Download the private key once.
5. Store App ID, private key and webhook secret in the `cloudlab` secret store (env file outside any
   git repo / Ansible vault / AKV per ADR 15) — placeholders `[REDACTED]` anywhere they'd be committed.

## §2 Deploy on `cloudlab`

```bash
git clone https://github.com/kodustech/kodus-installer.git && cd kodus-installer
# fill .env: GITHUB_APP_ID / GITHUB_APP_PRIVATE_KEY / GITHUB_WEBHOOK_SECRET (from §1)
# LLM (BYOK, zero markup): OpenAI-compatible endpoint
#   base URL https://api.mistral.ai/v1 · model mistral-large-4 · key = the Pro-plan MISTRAL_API_KEY
# (self-hosted infers the provider from the model name — kodustech/kodus-ai#1687 — so set the
#  generic OpenAI-compatible env explicitly rather than relying on the guess)
./scripts/install.sh        # generates secrets, creates networks, pulls ghcr.io/kodustech/* images
```

First deploy: plan 15–30 min, then health checks per the installer output. Stack = web UI, API,
worker, webhooks service, MCP manager + data stores (Docker Compose; Helm exists for k8s later).

## §3 Route the webhook publicly

Add a cloudflared/Caddy route on `cloudlab` (runbook 16 pattern): `kody.example.com` → Kodus
webhooks service, with a Cloudflare DNS record. Verify: GitHub App → Advanced → "Ping" returns 200.

## §4 POC run

1. In the Kodus UI, connect the `Homelab` repo; enable automatic review on PRs.
2. On the repo, **disable automatic Copilot code review** (Settings → Copilot) for the POC window so
   reviews aren't double-billed; manual "request Copilot review" stays available for the A/B.
3. Open 3–5 real PRs (or re-run recent ones); for each, also request a manual Copilot review.
4. Log per PR: model, wall-clock latency, Mistral usage (input/cached/output tokens → $), findings
   kept vs dismissed by the human reviewer, Copilot's findings on the same PR.

## §5 Teardown / rollback

`docker compose down` in the installer dir, uninstall the `homelab-kodus-poc` GitHub App
(settings/installations), remove the tunnel route + DNS record, re-enable Copilot auto review.
AGPLv3 note: personal/homelab use is fine; if the service is ever modified *and* served over a
network, the modifications must be published.

## Caveats

- Billing: one Mistral Pro key funds Kody's ML4 calls; the $15/mo shared allowance is consumed first,
  then prepaid PAYG — same meter as runbook 44's A/B, so watch Studio usage before/after.
- Context window: runbook 44 measured an 800k window for ML4 in Vibe; check what Kody sends and log it.
- Kody Rules (custom conventions) are the lever for repo-instruction adherence — seed them from
  `AGENTS.md` highlights during the POC.
- If the POC passes, promote to a proper Ansible workload (`ansible/workloads/kodus/`) and a
  `docs/workloads.md` row; until then this runbook is the whole record.
