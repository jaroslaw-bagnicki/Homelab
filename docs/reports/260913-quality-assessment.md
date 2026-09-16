# Project Quality Assessment — 2026-09-13

**Scope:** full assessment (process, documentation, decision log, IaC, operational readiness)
**Method:** artefact reading + live GitHub state (repo `jaroslaw-bagnicki/Homelab`)
**Baseline:** point-in-time snapshot at 2026-09-13, branch `docs/quality-assessment-prompt` (HEAD `ab217e2`)
**Amended:** 2026-09-15 — two changes since the snapshot: finding **3.1** (the ADR 19 contradiction) was fixed at source (its filename, every referrer, and ADR 24's bullet), and the CI remark was **suppressed** at the operator's direction — CI is deliberately deferred, so 3.5 is now recorded as a decision rather than an antipattern and 4.1 as out of scope rather than a gap.
**Amended:** 2026-09-16 — the CI decision now has an authoritative home: [ADR 32](../decisions/32-no-hosted-ci.md) ("No Hosted CI — Verification Stays Local"), which 3.5 and 4.1 point to. A report is the wrong place for a policy decision, so the deferral no longer rests on a snapshot. The same pass repaired the report's Low-severity findings — the broken links (3.6), the stale `adr-authoring` skill (3.7) and the state-doc drift (3.8) — and **narrowed 3.8**, retiring two sub-claims that did not survive re-verification (see 3.8).
**Amended:** 2026-09-16 — review remark on PR #118: the Trunk-Based cell asserted "PRs #109-#114: created and merged within 1-2 days". That range is not a set of merged PRs — **#111 is an issue** and **#112 was still open** — so the cell now names the four merged PRs (#109, #110, #113, #114) and labels the two exceptions. Every other PR reference in the report was re-checked (#95, #108, #110, #113 all merged).

---

## Executive Summary

This is a spare-time, single-operator homelab that is run like a small platform team's estate, and the
engineered part is genuinely strong: 31 ADRs in MADR form with an index and a template, 29 runbooks
(one carrying a per-sub-issue verification checklist), self-contained Ansible workload recipes, a
`CHANGELOG.md` wired into the PR rule, and a state-grouped status board with a "row leaves with the PR
that completes it" convention. Documentation-as-code discipline and change traceability are the
standout strengths; the operator also documents known debt candidly in PR bodies (PR #110 lists its own
deferred sweeps), which makes this audit easier but does not by itself schedule the work. The dominant
weakness is not craft but **currency**: the decision log contradicted itself on the Cloudflare origin
design (ADR 19 versus its own filename, index row, ADR 08, ADR 24 and the CHANGELOG — fixed 2026-09-15),
four ADR statuses are stale or outside the documented allowed set, the written security rule to sanitise
real domains is breached in 15 files by the committed personal domain `cloud5.ovh`, and the agent-facing
`adr-authoring` skill mandated a filename pattern and a "commit directly to `main`" workflow that
the repo abandoned (both repaired 2026-09-16 — see 3.7). Continuous integration is **deliberately out of scope** — the only check it could
add, `ansible-lint`, already runs locally — so verification rests on documented manual rules rather than
an enforced gate. Nothing found is structurally wrong, and the fixes are small: the time-critical one
(the ADR 19/24 contradiction that misdirected the edge-ingress migration in #65/#81) has been retired.

| Dimension | Rating (1-5) | Evidence |
|---|---|---|
| Decision hygiene | 4 | 31 ADRs, contiguous numbering, supersession links declared both ways (ADR 03->22, 08->19, 23->29); the ADR 19 contradiction is fixed (rename plus every referrer, 2026-09-15); residual: four stale statuses (3.2) |
| Backlog & roadmap hygiene | 3 | Excellent board (`docs/overview.md` states + Next step + parking lot); but 33 open issues, 10 unlabelled, superseded issues still open (#54, #62, #75) |
| Documentation currency | 4 | "state docs move together" rule, real sync discipline (PRs #95/#108/#113), and the drift it caught (3.6, 3.8) repaired in the same pass; residual: the two legends still disagree on glyph meaning, and nothing yet guards currency (4.2) |
| Infrastructure-as-Code discipline | 4 | Role/workload modularity, `host_vars` parameterisation, idempotent network declarations, Bicep + deploy script; but `Caddyfile.j2` hardcodes three hostnames the defaults file sanitises |
| Operational readiness | 3 | Runbook 29 checklist tagged per sub-issue; but ADR 02 backup dormant, no restore drill, no on-call/alert path |
| Security & secret hygiene | 3 | No secrets committed (pattern sweep clean), AKV-sourced credentials, `no_log`, restrictive `key_options`; but the real domain `cloud5.ovh` is committed in 15 files against an explicit rule |
| Change/release traceability | 4 | `CHANGELOG.md` newest-first with runbook/ADR links, "PR ships its changelog entry" rule, `Refs`/`Closes` discipline; one ADR-amendment PR without an entry |
| Verification & automation | 3 | `ansible-lint` and live `--diff` playbook runs are documented rules the operator runs locally, and runbooks carry completion criteria; CI is deliberately deferred (3.5/4.1), which leaves `docker/*/tests/verify-*.sh` unexecuted |

---

## 1. Framework identification

| Framework | Fit | Supporting practice / contradiction | Evidence |
|---|---|---|---|
| **Personal Kanban** | Strong | Four-state board (In progress / Planned / Held) + `## Not Scheduled` parking lot; every row has a **Next step**; rows are listed in execution order; a row is removed by the completing PR. No explicit WIP limit. | `docs/overview.md` "What's Next"; `.github/copilot-instructions.md` (board states); `AGENTS.md` |
| **GitHub Flow** | Strong | Feature branch -> push -> PR on request -> review -> merge; "never commit to `main`"; PR opened only on explicit user request; squash merges (48 commits -> one `main` commit on #113). | `AGENTS.md` "Worktree Workflow"; `.github/copilot-instructions.md` "Git Workflow"; PR #113 |
| **Trunk-Based Development** | Moderate | Single `main` trunk and mostly same-day short-lived branches (the four merged PRs #109, #110, #113, #114 were each created and merged within 1-2 days; #111 in that range is an issue, not a PR). Contradicted by a 1-day-open branch at audit time (`feat/netdata-parent-role`, PR #112, still open) and by the overlap between #109 and #113 on the same subject. No CI gate, so "trunk always green" is untested. | PR #112 (open); PRs #109 + #113 |
| **Docs-as-Code** | Strong | Numbered `docs/ideas|research|decisions|runbooks` each with a `README.md` index, plus `docs/README.md` as the area index; every doc change lands through the same PR review as code. | `docs/README.md`; every recent PR |
| **ADR / MADR practice** | Strong structure, Moderate currency | `docs/decisions/TEMPLATE.md`, `adr-authoring` skill, newest-first index, in-place amendments with a dated banner (ADR 09, ADR 24, ADR 27), explicit `Supersedes` front-matter and closing banners. Currency fails: see antipatterns 1 and 3. | `docs/decisions/README.md`, `TEMPLATE.md`, ADRs 09/24/27 |
| **Infrastructure as Code** | Strong | Declarative Ansible roles + per-host `host_vars`; workloads self-contained and independently runnable; Bicep for the cloud side with an idempotent deploy script; Ansible-side READMEs carry the facts. | `ansible/roles/**`, `ansible/workloads/**`, `bicep/main.bicep` + `Deploy-HomelabAzResources.ps1` |
| **Runbook-driven operations (SRE/ITIL-lite)** | Strong | 29 runbooks; runbook 29 carries a "Verification Checklist" whose rows are tagged with the sub-issue that owns them (`[#116]`, `[#117]`); runbook 28 records the verified date. No incident/change-management layer (appropriate at this scale). | `docs/runbooks/29-nut-ups-shutdown.md` "Verification Checklist"; runbook 28 |
| **Shape Up** | Moderate | Appetite-style effort sizing on the board (`*` one session / `**` a few sessions / `***` multi-week or hardware-gated) and explicit sequencing. No cycles, betting table, or cool-down, so this is effort sizing rather than Shape Up. | `docs/overview.md` effort legend |
| **Scrum / SAFe / PMBOK** | Weak / absent | No sprints, roles, ceremonies, estimates, or portfolio artefacts. Deliberate: ADR 11 rejects Jira and GitHub Projects as "overkill for a single-person hobby project". | ADR 11 "Rejected Options" |
| **XP** | Weak | Partial alignment only: small scoped commits, one-logical-change-per-commit, and PR-time review (Copilot review plus the operator reading *suppressed* comments). No TDD and no continuous integration, so the XP loop is half-present. | `AGENTS.md` "Scope commits tightly"; PR #110 review summary (suppressed comments) |

---

## 2. Best practices in use

### Process & Workflow
- **Branch -> PR -> review -> merge, never a direct `main` commit**, with an explicit carve-out list for when direct commits are allowed. (`.github/copilot-instructions.md` "Git Workflow"; `AGENTS.md` "Worktree Workflow")
- **Self-restraining agent rule**: a PR is opened only on explicit user request, in both instruction files. (PR #110 shipped this rule)
- **`CHANGELOG.md` entry ships in the same PR** as the behaviour/doc change, newest first, with runbook/ADR links. (CHANGELOG preamble; PR #113 body)
- **Issue/PR titles carry no `(type)` prefix**; labels convey type. (`.github/copilot-instructions.md` "Issue Tracking"; PR titles #99-#114 comply)
- **PR descriptions use plain `## Changes` / `## Notes`**, with WWH reserved for issues. (PRs #110, #113)
- **Board hygiene as a rule, not a habit**: state groups, a concrete `Next step` per row, and "a row leaves the table with the PR that completes it". (`docs/overview.md`; `AGENTS.md`)
- **Plan/build separation** with an explicit read-only planning phase and one-plan-step-at-a-time acceptance. (`AGENTS.md` "Plan -> Build Transition")

### Documentation & Decision Hygiene
- **ADR log with a template and a skill**, plus in-place amendment banners that keep a revised decision readable rather than silently rewriting history (ADR 09, 24, 27).
- **"Research settles, ADR owns" co-authoring rule** - the ADR is authored in the same phase as the research, and the research doc defers authority. (`AGENTS.md` "Documentation"; idea 09 -> ADR 30)
- **`Supersedes` declared on both sides** - ADR 03/22, ADR 08/19, ADR 23/29 all cross-link.
- **State docs move together** for any node status change, with the Copilot reviewer catching mismatches. (`.github/copilot-instructions.md`)
- **Idea lifecycle stated** (Idea -> Planned -> Implementing -> Done) with ADR cross-references. (`docs/ideas/README.md`)
- **PR bodies record deliberately deferred work**, which is unusually honest engineering hygiene. (PR #110 Notes)

### Infrastructure & Engineering
- **Modular, independently runnable workloads** that never import each other, with idempotent duplicate declarations permitted and "first writer wins" documented. (`docs/workloads.md` "Convention rules")
- **Inventory-driven host set with a guard**: `docker_services` asserts `inventory_hostname in ['lab','cloudlab']` and tells the reader which file to update. (`ansible/roles/docker_services/tasks/main.yml`)
- **Least privilege by default**: `docker_users: []` everywhere, with the rationale (passwordless root via the socket) written next to it. (`ansible/README.md` "Agent account pattern")
- **Secrets from Key Vault with `no_log: true`** and a `.env` written `mode: "0600"`. (`ansible/roles/docker_services/tasks/main.yml`)
- **Scripts print the read-back command, never the secret.** (`scripts/New-HomelabNutUpsmonPasswords.ps1`, `New-HomelabZotRegistryCredential.ps1`)
- **Pinned dev environment**: devcontainer features plus `devcontainer-lock.json`; PowerShell as the default terminal; Az PowerShell over `az` CLI as a stated rule.
- **Per-project container images with smoke-test scripts** (`docker/*/tests/verify-*.sh`).

### Operations & Security
- **Runbook completion criteria are real** - runbook 29's checklist distinguishes delivered (`[x]`) from outstanding (`[ ]`) and names the owning issue for each gap.
- **Fleet SSH as one rotatable unit**: private key in AKV and ssh-agent only, public key committed (not a secret), `exclusive: true` plus `key_options` restricting forwarding and X11. (ADR 28; `ansible/roles/common/tasks/main.yml`)
- **UFW default-deny, fail2ban, key-only SSH with a scoped LAN password carve-out closed by `Match all`.** (`ansible/roles/security/tasks/main.yml`)
- **Credential-pattern sweep came back clean** - the only match is a placeholder (`YOUR_TOKEN_PLAN_SUBSCRIPTION_KEY`).

---

## 3. Antipatterns detected

### 3.1 Decision-log self-contradiction on the Cloudflare origin design
- **What**: ADR 19's file now records "Cloudflare Tunnel **HTTP** origin with Caddy reverse proxy on Cloudlab" and explicitly abandons the Origin CA / Full (Strict) approach - yet its **filename** is `19-cloudflare-tunnel-https-origin.md`, its **index title** is "HTTPS-only origin via Cloudflare Tunnel + Cloudflare Origin CA on Cloudlab", **ADR 08** names ADR 19 as the "HTTPS-only origin" replacement, **ADR 24** instructs "cloudflared -> Caddy over HTTPS with Cloudflare Origin CA; CF SSL mode Full (Strict)", and the **CHANGELOG** entry records an "HTTPS-only origin" change. The code follows ADR 19's revised decision (`Caddyfile.j2` serves `http://` blocks; runbook 20 states "origin traffic is plain HTTP").
- **Why it matters here**: ADR 24 is the *governing* ADR for the in-progress edge-ingress migration (#65/#81). An agent or the operator reading the decision log to build that migration is told, by an Accepted ADR, to implement a design that a sibling Accepted ADR explicitly rejected - exactly the "why did we pick X over Y?" question the log exists to answer.
- **Severity**: **High** - actively misdirected the next implementation step. **Fixed 2026-09-15.**
- **Evidence**: `docs/decisions/19-cloudflare-tunnel-https-origin.md` (title, Status, "Original HTTPS-to-origin approach (superseded)"), `docs/decisions/README.md` row 19, `docs/decisions/08-remote-access-cloudflare-tunnel.md` "Superseded by ADR 19", `docs/decisions/24-edge-ingress-appliance.md` Decision bullet 4, `CHANGELOG.md` (2026-07 `cloudflared` entry), `docs/runbooks/20-deploy-zot.md` (traffic flow line).
- **Fixed**: ADR 19 renamed to `19-cloudflare-tunnel-http-origin.md` with an `**Amended:**` line recording the in-place revision; index rows 8 and 19, ADR 08 (status, supersession section, references), ADR 24 (decision bullet, references), idea 04, research 25, runbooks 16/17/20/23/24 and the 2026-07 changelog entry all now describe the plain-HTTP origin. Verified: no reference to the old filename remains. The fix needed no workflow - CI is out of scope (3.5).

### 3.2 Stale decision statuses
- **What**: statuses outside the documented allowed set or no longer true. ADR 02 is "In Progress" (not an allowed value; dormant since June). ADR 09 is "Implemented (partial)" (not an allowed value). ADR 25 is "Proposed" although its own promotion criteria - the hardware purchased and the dedicated-node trade-off closed - were met on 2026-08-19/2026-09-06. ADR 28's Status line says "`lab` and `edge` pending" while the `fleet-connect` skill states the fleet-wide migration "completed 2026-08-30" and the CHANGELOG records edge key-only SSH shipped.
- **Why it matters here**: status is the one field the agent and the operator scan first. "Proposed" on ADR 25 suppresses it as a governing decision for the HA build; "pending" in ADR 28 understates DR readiness.
- **Severity**: **Medium**
- **Evidence**: `docs/decisions/README.md` (status set + rows 02, 09, 25), `docs/decisions/25-home-assistant-thin-client.md` ("Proposed -> Accepted" paragraph), `docs/decisions/28-fleet-admin-account-and-key.md` "Status" line, `.github/skills/fleet-connect/SKILL.md`.
- **Existing mitigation**: partial - `docs/overview.md` "Not Scheduled" explicitly flags ADR 02's stale status, so it is known but not fixed.

### 3.3 The domain-sanitisation rule is breached at scale
- **What**: both instruction files require replacing any real personal domain with `example.com` "in all documentation, configs, and code before committing. The repo is public." The real domain `cloud5.ovh` appears in **15 tracked files / 41 matches**, including deployment code (`.devcontainer/config/profile.ps1`, `scripts/*.ps1`, `docker/opencode-*/Dockerfile`) and a config template that the defaults file deliberately sanitises (`roles/docker_services/defaults/main.yml` sets `example.com`, while `templates/Caddyfile.j2` hardcodes `http://cloud5.ovh`, `hello.cloud5.ovh` and `portainer.cloud5.ovh`).
- **Why it matters here**: the rule is load-bearing for a public repo, and a rule that is broken in 15 places trains the operator and the agent to ignore it. The template/defaults split is also a live correctness bug: the apex/hello/portainer hostnames are not parameterised, so changing the domain silently leaves three routes behind.
- **Severity**: **Medium** (security rule drift + config parameterisation bug)
- **Evidence**: `.github/copilot-instructions.md` and `AGENTS.md` "Security"; grep of `cloud5.ovh`; `ansible/roles/docker_services/templates/Caddyfile.j2` lines 1/5/9 vs `defaults/main.yml`.
- **Existing mitigation**: none.

### 3.4 Backlog rot and untriaged issues
- **What**: 33 open issues. Ten carry **no label** (#13, #16, #34, #36, #39, #43, #44, #48, #104, #107). Three are superseded by accepted decisions but remain open: #54 (ML110 NAS) and #62 (ML110 Phase 2) after ADR 29 made the ML110 a retiring node, and #75 (monitoring reconciliation) after ADR 27 settled it. Eleven have had no activity since June/July (#3, #4, #13, #16, #33, #34, #36, #38, #39, #43, #48). Four titles still carry `(feat)`/`(research)` prefixes from before the naming rule (#3, #4, #57, #58).
- **Why it matters here**: this is the one workstream the board rule does **not** cover, and the only place the debt was recorded is a PR body (PR #110 Notes names the dormant sweep by issue number) - which is not a durable backlog artefact and will not be re-read.
- **Severity**: **Medium**
- **Evidence**: `list_issues` (open, 33); PR #110 Notes ("Deliberately outside this PR: ... the dormant-issue backlog sweep (#16, #34, #36, #38, #39, #43, #48, #53, #57, #58)"); `docs/overview.md` "Not Scheduled" (covers only #13, #3, #4).
- **Existing mitigation**: partial - the board parks three dormant items and the CHANGELOG records `#94` as shipped-and-removed.

### 3.5 Automated verification - deliberately deferred (recorded, not an antipattern)
- **What**: the repo has no `.github/workflows`, and that is a decision rather than an omission: **CI is out of scope for this project**. The only check a pipeline would meaningfully add is `ansible-lint` on changed roles, which is already a documented pre-commit rule (`AGENTS.md` "Ansible Verification") and runs locally in seconds. The `docker/*/tests/verify-*.sh` smoke tests and a Markdown link check are not worth a pipeline on a single-operator repo that merges a few times a week.
- **Why it is recorded here**: so a future audit does not re-derive it as a finding. The compensating controls are the documented local lint step, PR-time Copilot review, and the runbook completion checklists.
- **Severity**: **Negligible** (accepted trade-off - operator decision, 2026-09-15)
- **Recorded as**: [`ADR 32`](../decisions/32-no-hosted-ci.md) (2026-09-16) - the decision now has an authoritative home instead of living in this snapshot, and both instruction files carry a one-line pointer so an agent session stops re-proposing a pipeline.
- **Evidence**: `.github/` listing; `AGENTS.md` "Ansible Verification"; `docker/*/tests/`.

### 3.6 Documentation link rot and stale cross-references
- **What**: `docs/opencode-customization/README.md` linked runbooks and ADRs with paths relative to its own folder (`runbooks/17-...`, `decisions/16-...`) but no such subfolders exist - 8 broken links (`../runbooks/`, `../decisions/` resolve). ADR 10 cited `260613-backup-strategy-restic-blob.md`, a filename that never existed. ADR 13 cited `research/15-vps-selection.md` from inside `docs/decisions/` instead of `../research/`. `docs/runbooks/README.md` carries no explanation for the missing runbook number 08 (verified: it was never tracked).
- **Why it matters here**: the ADR/research/runbook cross-links are the primary navigation path for both the operator and the agent.
- **Severity**: **Low** - fixed 2026-09-16.
- **Evidence**: `docs/opencode-customization/README.md` (runbook + ADR indexes); `docs/decisions/10-ansible-host-config.md` Decision/Scope bullet; `docs/decisions/13-cloudlab-staging.md` References; `git log --all -- 'docs/runbooks/08*'` (empty).
- **Fixed**: all 8 links now resolve via `../`; ADR 10's filename becomes `02-backup-strategy-restic-blob.md`; ADR 13's two `research/*` links become `../research/*`.
- **Residual**: ADR 10's *prose* code spans (`research/13-…`, `runbooks/01-…`) point one level too shallow but are not links and do not 404, so they were left alone rather than churned; the runbook index's missing 08 is a renumbering artifact from PR #64, not a defect. Nothing guards this class - that is gap 4.2.

### 3.7 The `adr-authoring` skill contradicts the repo it governs
- **What**: the skill mandated `docs/decisions/YYMMDD-NN-kebab-case-title.md` filenames (no file in the repo uses that form) and ended with "**Commit directly to `main`** (per Homelab workflow)" - the exact opposite of the current branch -> PR rule in both instruction files. It also routed "writing research docs" to a "research-output skill" that does not exist (`skills/` holds `adr-authoring`, `fleet-connect`, `gemini-thread-summary`, `grill-me`).
- **Why it matters here**: skills are read by the agent as authoritative *rules*, so this is a Rule-vs-Rule conflict, not just stale prose. It is already acknowledged in PR #110's Notes as deliberately deferred.
- **Severity**: **Medium** - fixed 2026-09-16.
- **Evidence**: `.github/skills/adr-authoring/SKILL.md` "File naming" + "Commit conventions" + description; actual filenames `docs/decisions/01-*.md` .. `32-*.md`; `.github/skills/` listing.
- **Fixed**: the filename pattern is now `NN-kebab-case-title.md`, with a note that the `YYMMDD-NN-*` form was never adopted; "commit directly to `main`" is replaced by the branch -> PR rule (plus the `CHANGELOG.md` requirement); the pointer to a non-existent "research-output skill" is dropped; and ADR 12 gains an `**Amended:**` line so the decision log no longer contradicts its own skill.

### 3.8 State-doc drift below the "move together" rule
- **What**: `docs/hardware.md` HA node Status read "HA VM/LXC still pending (#68 / #85)" while `docs/overview.md` reported the NUT LXC 213 server side delivered ([#115]) and ADR 30 is Accepted on the same node. Two idea rows lagged delivery: idea 01c was "Planned" though ADR 29 is Accepted and the unit was in hand, and idea 05 was "Planned" though the Proxmox base had been installed and provisioned (runbook 28). The two legends also reuse the same glyphs with different meanings (`docs/overview.md` uses a running icon for ✅; `docs/ideas/README.md` uses it for "Done").
- **Why it matters here**: the "overview + hardware move together" rule works at the node-row level but not at the sub-node (guest/LXC) or idea-status level, which is where the truth now lives.
- **Severity**: **Low**
- **Evidence**: `docs/hardware.md` HA "Status" row; `docs/overview.md` Nodes table + UPS row; `docs/ideas/README.md` rows 01c/05; both legend lines.
- **Withdrawn after re-verification (2026-09-16)**: two earlier sub-claims did not survive checking and are retracted rather than carried. Idea 04's "Implementing" is *correct* — ADR 24 is Accepted and `edge_host` shipped, but the ingress **migration** in #65/#81 that the idea describes has not happened. The topology diagram showing the OMV NAS at `.210` is *correct* too — ADR 31 keeps `.210` occupied until the ML110 retires, and the diagram reflects what is actually wired rather than what is planned; omitting the unbuilt Beetle and the uninstalled OPNsense is a presentation choice, not drift.
- **Fixed**: the `hardware.md` HA line now separates the delivered LXC 213 from the pending HA OS VM and LXC 211/212, and idea 01c/05 move to "Implementing". The legend clash is left in place — it is cosmetic, and rewriting two legends to buy nothing is churn.
- **Residual**: nothing enforces this class of currency; that is gap 4.2, and the rule still depends on the operator (or reviewer) noticing.

### 3.9 WIP load and branch litter
- **What**: five rows sit in "In progress" at once (one `***`, three `**`), which for a spare-time single operator is closer to a plan than a limit - though most are hardware- or sequence-gated rather than actively parallel. Two PRs covered the same UPS subject within two days (#109 then #113). Five merged head branches remain on the remote (`docs/nut-runbook`, `docs/beetle-m3-reaudit`, `docs/refresh-overview-whats-next`, `feat/ups-nut-home-assistant`, plus the open `feat/netdata-parent-role`), because GitHub does not delete remote head branches on merge.
- **Why it matters here**: low-grade; the branch retention is a known, accepted platform behaviour, and the WIP rows are mostly legitimate gates. Noted so it does not become a trend.
- **Severity**: **Low**
- **Evidence**: `docs/overview.md` "In progress" (5 rows); PRs #109/#113; `git branch -r` (6 non-main branches).
- **Existing mitigation**: repo memory records the "GitHub does not delete remote head branches" behaviour, so this is a conscious trade-off.

### 3.10 Ceremony above the minimum - **Negligible**
- **What**: four documentation areas with indexes, a template, a skill, a board, a parking lot, and a changelog for one person.
- **Why**: it would be over-engineering in most one-person repos. Here it demonstrably pays - the ADRs are the agent's context, the board drives sequencing, and the changelog is the only durable release record. **Note only; do not reduce.**
- **Evidence**: `docs/` tree; `CHANGELOG.md`; `docs/overview.md`.

---

## 4. Gaps and recommendations

### 4.1 CI gate - out of scope by decision
- **Not a gap**: CI is deliberately deferred (see 3.5), and the decision is now recorded as [`ADR 32`](../decisions/32-no-hosted-ci.md). `ansible-lint` already runs locally as a documented pre-commit rule and is the only check a workflow would usefully add; a pipeline for Markdown links or the image smoke tests is not worth the maintenance on a single-operator repo.
- **What would change that**: ADR 32's "Revisit if" list - a second contributor, a check that cannot be run locally, or a release needing an auditable build record.
- **Effort**: n/a - the decision is made, not pending.
- **Issue?** No.

### 4.2 No automated currency check for the decision log and board
- **Missing**: nothing verifies ADR status values, index-title/filename parity, that a superseded ADR names its successor, or that a board row references a live issue. Findings 3.1, 3.2, 3.6 and 3.8 are all in this class.
- **Lightweight fix**: a `scripts/Test-HomelabDocs.ps1` that asserts (i) every `**Status:**` value is in the allowed set, (ii) every ADR row in `docs/decisions/README.md` links a file that exists and whose `#` title matches the row, (iii) every `Superseded by` target exists, (iv) every relative link in `docs/**/*.md` resolves, and (v) every `#NNN` on the board resolves to an open issue. Run it locally alongside `ansible-lint` as part of the existing pre-commit rule - no CI needed (3.5). This is the single highest-yield guard for this repo's failure mode, and it stays a script rather than a pipeline.
- **Effort**: Low (one session, one script).
- **Issue?** Yes - one issue covering this and the backlog sweep (4.6).

### 4.3 Backup and restore are unverified
- **Missing**: ADR 02's Restic path is dormant, there is no scheduled backup job, and no restore drill exists even though the storage layer is being replatformed (ML110 -> Beetle). ADR 22 already flags the Velero/Longhorn gap.
- **Lightweight fix**: a "Restore drill" section in the existing backup runbook (runbook 07) with a definite pass condition (restore one named artefact and diff it), plus a board row; keep Restic as-is until the Beetle array is verified.
- **Effort**: Medium (a few sessions; partly hardware-gated on the Beetle).
- **Issue?** Yes - it is multi-session and currently invisible on the board.

### 4.4 Domain-sanitisation guard
- **Missing**: nothing prevents the next `cloud5.ovh` from being committed.
- **Lightweight fix**: parameterise the three hardcoded hostnames in `Caddyfile.j2` through a `cloudlab_public_domain` (or reuse `opencode_public_domain`) so they match the defaults-file pattern, sanitise `docs/` and `scripts/` to `example.com`, then add a workflow grep that fails on the real domain outside an explicit allowlist (`ansible/host_vars/cloudlab.yml` is the one place it may legitimately live).
- **Effort**: Low-Medium.
- **Issue?** No - one focused PR.

### 4.5 Idea/ADR lifecycle close-out
- **Missing**: no step says "when the work ships, update the ADR status and the idea index row". Idea 04/01c and ADR 25/02/09/28 all show the gap.
- **Lightweight fix**: add two lines to the `adr-authoring` skill - (i) fix the filename convention to `NN-kebab.md` and replace "commit directly to `main`" with "one ADR + its index row per PR", (ii) "when a decision ships, set the status to Implemented and move the originating idea row to Done in the same PR". The skill repair also resolves 3.7.
- **Effort**: Low (docs-only).
- **Issue?** No - one focused PR.

### 4.6 Backlog reconciliation pass
- **Missing**: a triage step. Ten unlabelled issues, three superseded-but-open, eleven dormant.
- **Lightweight fix**: one sweep - label everything, close #54/#62/#75 as superseded (referencing ADR 29/27), and park the genuinely dormant ones in `## Not Scheduled` (which already exists for exactly this purpose). Then add a board-sweep line to the "Definition of Done" bullet already in the instructions.
- **Effort**: Low.
- **Issue?** Yes - a single tracking issue so the sweep is not lost again in a PR body.

### 4.7 WIP visibility (optional)
- **Missing**: no stated WIP limit.
- **Lightweight fix**: one line in the board section - "In progress: maximum three rows; a fourth means park or finish" - or explicitly state that hardware-gated rows do not count.
- **Effort**: Low.
- **Issue?** No.

---

## Top 3 actions

1. **Verify backup and restore** - the highest remaining severity (4.3). ADR 02 is dormant, no restore drill exists, and the storage layer is being replatformed (ML110 -> Beetle). Add a "Restore drill" section with a definite pass condition to runbook 07, and a board row. Files: `docs/runbooks/07-restic-backup.md`, `docs/overview.md`, `docs/decisions/02-backup-strategy-restic-blob.md`.
2. **One doc-currency PR** - sanitise the real domain and parameterise the three hardcoded `Caddyfile.j2` hostnames (3.3), fix the `adr-authoring` skill's filename pattern and `main`-commit rule (3.7), and correct the stale statuses (ADR 02, 09, 25, 28) and idea rows (01c, 04) - files: `ansible/roles/docker_services/templates/Caddyfile.j2`, `docs/decisions/*`, `docs/ideas/README.md`, `.github/skills/adr-authoring/SKILL.md`.
3. **Add the local docs-currency check** - `scripts/Test-HomelabDocs.ps1` (4.2), run alongside `ansible-lint` per the existing pre-commit rule, so the class of drift this audit found (3.1, 3.2, 3.6, 3.8) cannot silently return. No CI required.

> **Retired:** the original action 1 (retire the ADR 19 contradiction) was completed on 2026-09-15 - see 3.1. The original action 2 (add a CI workflow) was withdrawn: CI is deliberately out of scope - see 3.5.

---

## Summary table

| # | Finding | Type | Severity | Evidence |
|---|---|---|---|---|
| 3.1 | ADR 19's decision contradicted its filename, index row, ADR 08, ADR 24 and the CHANGELOG | Antipattern | High - **fixed 2026-09-15** | `docs/decisions/19-*.md`, `decisions/README.md` row 19, ADR 08 "Superseded by", ADR 24 Decision, CHANGELOG 2026-07 |
| 3.2 | Stale / out-of-set ADR statuses (02, 09, 25, 28) | Antipattern | Medium | `docs/decisions/README.md`, ADR 25 promotion paragraph, ADR 28 Status line |
| 3.3 | Real domain `cloud5.ovh` committed in 15 files; `Caddyfile.j2` hostnames unparameterised | Antipattern | Medium | `.github/copilot-instructions.md` Security; `Caddyfile.j2` L1/5/9 vs `docker_services/defaults/main.yml` |
| 3.4 | 33 open issues: 10 unlabelled, 3 superseded-but-open, 11 dormant | Antipattern | Medium | `list_issues`; PR #110 Notes |
| 3.5 | Automatic verification is deliberately deferred, not missing | Recorded decision | Negligible (accepted) | `.github/` has no `workflows/`; `AGENTS.md` Ansible Verification; `docker/*/tests/` |
| 3.6 | Broken relative links + a non-existent ADR-10 filename; runbook 08 gap | Antipattern | Low - **fixed 2026-09-16** | `docs/opencode-customization/README.md`; `docs/decisions/10-*.md`; `git log -- docs/runbooks/08*` |
| 3.7 | `adr-authoring` skill mandated a dead filename pattern and "commit directly to `main`" | Antipattern | Medium - **fixed 2026-09-16** | `.github/skills/adr-authoring/SKILL.md` |
| 3.8 | `hardware.md` HA status vs `overview.md`; two idea statuses lagged; legend clash (two further claims withdrawn) | Antipattern | Low - **fixed 2026-09-16** | `docs/hardware.md` HA Status; `docs/overview.md`; `docs/ideas/README.md` rows 01c/05 |
| 3.9 | 5 concurrent "In progress" rows; 5 merged head branches on the remote | Antipattern | Low | `docs/overview.md`; `git branch -r` |
| 3.10 | Documentation ceremony above the minimum for one person | Antipattern | Negligible | `docs/` tree; `CHANGELOG.md` |
| 4.1 | CI gate - out of scope by decision (see 3.5) | Recorded decision | Out of scope | `.github/`; `AGENTS.md` Ansible Verification |
| 4.2 | No automated decision-log / board currency check | Gap | Medium / Low effort | `docs/decisions/README.md`; `docs/overview.md` |
| 4.3 | Backup and restore unverified; ADR 02 dormant | Gap | High / Medium effort | ADR 02 Status; `docs/overview.md` Not Scheduled |
| 4.4 | No domain-sanitisation guard | Gap | Medium / Low-Medium effort | `Caddyfile.j2`; `.github/copilot-instructions.md` Security |
| 4.5 | No idea/ADR lifecycle close-out step | Gap | Medium / Low effort | ADR 25; `docs/ideas/README.md` |
| 4.6 | No backlog triage pass | Gap | Medium / Low effort | `list_issues`; PR #110 Notes |
| 4.7 | No stated WIP limit | Gap | Low / Low effort | `docs/overview.md` "In progress" |

---

## Limitations

- **Merge state ambiguity.** The GitHub MCP `list_pull_requests` response reported `"merged": false` while populating `merged_at` for every closed PR. I treated these as merged (consistent with the repo's squash-merge convention and the CHANGELOG entries). This affects branch-litter counting, not any finding.
- **PR body sampling.** Only PRs #110 and #113 had their full bodies read. The "no WWH in PR descriptions" and "titles free of `(type)`" checks are therefore verified against the last 25 titles plus two bodies, not all 113 PRs.
- **Review-remark practice not re-verified.** The PR-review workflow (including reading the suppressed-comment section rather than `get_review_comments` alone) is evidenced from the repo memory and PR #110's own summary, not from re-fetching review threads.
- **Idea and research docs were not read in full.** 32 research and 10 idea documents exist; findings about their statuses come from `docs/ideas/README.md` rows and the ADRs that consume them. A research doc could carry its own settled-but-unrecorded decision that this audit would not see.
- **No runtime verification.** Neither `ansible-lint` nor any playbook was executed, and no fleet host was probed. All IaC and operations findings are structural (file-level), not runtime-confirmed. Live state (LXC 213, edge OS, Beetle progress) is taken from the repo docs and PR bodies.
- **External links and cost/pricing claims were not checked.** Link integrity was assessed for repo-internal relative paths only.
