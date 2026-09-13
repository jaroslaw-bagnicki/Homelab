# Project Quality Assessment — 2026-09-13

**Scope:** full assessment (process, documentation, decision log, IaC, operational readiness)
**Method:** artefact reading + live GitHub state (repo `jaroslaw-bagnicki/Homelab`)
**Baseline:** point-in-time snapshot at 2026-09-13, branch `docs/quality-assessment-prompt` (HEAD `ab217e2`)

---

## Executive Summary

This is a spare-time, single-operator homelab that is run like a small platform team's estate, and the
engineered part is genuinely strong: 31 ADRs in MADR form with an index and a template, 29 runbooks
(one carrying a per-sub-issue verification checklist), self-contained Ansible workload recipes, a
`CHANGELOG.md` wired into the PR rule, and a state-grouped status board with a "row leaves with the PR
that completes it" convention. Documentation-as-code discipline and change traceability are the
standout strengths; the operator also documents known debt candidly in PR bodies (PR #110 lists its own
deferred sweeps), which makes this audit easier but does not by itself schedule the work. The dominant
weakness is not craft but **currency and enforcement**: the decision log contradicts itself on the
Cloudflare origin design (ADR 19 versus its own filename, index row, ADR 08, ADR 24 and the CHANGELOG),
four ADR statuses are stale or outside the documented allowed set, and there is **no CI whatsoever**, so
every lint, test and live-playbook check is honour-system. The written security rule to sanitise real
domains is breached in 15 files by the committed personal domain `cloud5.ovh`, and the agent-facing
`adr-authoring` skill still mandates a filename pattern and a "commit directly to `main`" workflow that
the repo abandoned. Nothing found is structurally wrong; the fixes are small, and the highest-value one
(retiring the ADR 19/24 contradiction) is time-critical because it directly misdirects the edge-ingress
migration (#65/#81) that is next in the queue.

| Dimension | Rating (1-5) | Evidence |
|---|---|---|
| Decision hygiene | 3 | 31 ADRs, contiguous numbering, supersession links (ADR 03->22, 08->19, 23->29); but ADR 19 vs index/ADR 08/ADR 24/CHANGELOG contradict; ADR 02 "In Progress" and ADR 09 "Implemented (partial)" are outside the documented allowed set |
| Backlog & roadmap hygiene | 3 | Excellent board (`docs/overview.md` states + Next step + parking lot); but 33 open issues, 10 unlabelled, superseded issues still open (#54, #62, #75) |
| Documentation currency | 3 | "state docs move together" rule and real sync discipline (PRs #95/#108/#113); but `hardware.md` HA status vs `overview.md`, idea statuses, and broken relative links |
| Infrastructure-as-Code discipline | 4 | Role/workload modularity, `host_vars` parameterisation, idempotent network declarations, Bicep + deploy script; but `Caddyfile.j2` hardcodes three hostnames the defaults file sanitises |
| Operational readiness | 3 | Runbook 29 checklist tagged per sub-issue; but ADR 02 backup dormant, no restore drill, no on-call/alert path |
| Security & secret hygiene | 3 | No secrets committed (pattern sweep clean), AKV-sourced credentials, `no_log`, restrictive `key_options`; but the real domain `cloud5.ovh` is committed in 15 files against an explicit rule |
| Change/release traceability | 4 | `CHANGELOG.md` newest-first with runbook/ADR links, "PR ships its changelog entry" rule, `Refs`/`Closes` discipline; one ADR-amendment PR without an entry |
| Verification & automation | 2 | Zero `.github/workflows`; `ansible-lint` and live-playbook tests are documented rules only; `docker/*/tests/verify-*.sh` exist but are never executed automatically |

---

## 1. Framework identification

| Framework | Fit | Supporting practice / contradiction | Evidence |
|---|---|---|---|
| **Personal Kanban** | Strong | Four-state board (In progress / Planned / Held) + `## Not Scheduled` parking lot; every row has a **Next step**; rows are listed in execution order; a row is removed by the completing PR. No explicit WIP limit. | `docs/overview.md` "What's Next"; `.github/copilot-instructions.md` (board states); `AGENTS.md` |
| **GitHub Flow** | Strong | Feature branch -> push -> PR on request -> review -> merge; "never commit to `main`"; PR opened only on explicit user request; squash merges (48 commits -> one `main` commit on #113). | `AGENTS.md` "Worktree Workflow"; `.github/copilot-instructions.md` "Git Workflow"; PR #113 |
| **Trunk-Based Development** | Moderate | Single `main` trunk and mostly same-day short-lived branches (PRs #109-#114: created and merged within 1-2 days). Contradicted by a 1-day-open branch at audit time (`feat/netdata-parent-role`, PR #112) and by the overlap between #109 and #113 on the same subject. No CI gate, so "trunk always green" is untested. | PR #112 (open); PRs #109 + #113 |
| **Docs-as-Code** | Strong | Numbered `docs/ideas|research|decisions|runbooks` each with a `README.md` index, plus `docs/README.md` as the area index; every doc change lands through the same PR review as code. | `docs/README.md`; every recent PR |
| **ADR / MADR practice** | Strong structure, Moderate currency | `docs/decisions/TEMPLATE.md`, `adr-authoring` skill, newest-first index, in-place amendments with a dated banner (ADR 09, ADR 24, ADR 27), explicit `Supersedes` front-matter and closing banners. Currency fails: see antipatterns 1 and 3. | `docs/decisions/README.md`, `TEMPLATE.md`, ADRs 09/24/27 |
| **Infrastructure as Code** | Strong | Declarative Ansible roles + per-host `host_vars`; workloads self-contained and independently runnable; Bicep for the cloud side with an idempotent deploy script; Ansible-side READMEs carry the facts. | `ansible/roles/**`, `ansible/workloads/**`, `bicep/main.bicep` + `Deploy-HomelabAzResources.ps1` |
| **Runbook-driven operations (SRE/ITIL-lite)** | Strong | 29 runbooks; runbook 29 carries a "Verification Checklist" whose rows are tagged with the sub-issue that owns them (`[#116]`, `[#117]`); runbook 28 records the verified date. No incident/change-management layer (appropriate at this scale). | `docs/runbooks/29-nut-ups-shutdown.md` "Verification Checklist"; runbook 28 |
| **Shape Up** | Moderate | Appetite-style effort sizing on the board (`*` one session / `**` a few sessions / `***` multi-week or hardware-gated) and explicit sequencing. No cycles, betting table, or cool-down, so this is effort sizing rather than Shape Up. | `docs/overview.md` effort legend |
| **Scrum / SAFe / PMBOK** | Weak / absent | No sprints, roles, ceremonies, estimates, or portfolio artefacts. Deliberate: ADR 11 rejects Jira and GitHub Projects as "overkill for a single-person hobby project". | ADR 11 "Rejected Options" |
| **XP** | Weak | Partial alignment only: small scoped commits, one-logical-change-per-commit, and PR-time review (Copilot review plus the operator reading *suppressed* comments). No TDD and no continuous integration, so the XP loop is half-present. | `AGENTS.md` "Scope commits tightly"; repo memory (suppressed-comment practice) |

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
- **Severity**: **High** - actively misdirects the next implementation step.
- **Evidence**: `docs/decisions/19-cloudflare-tunnel-https-origin.md` (title, Status, "Original HTTPS-to-origin approach (superseded)"), `docs/decisions/README.md` row 19, `docs/decisions/08-remote-access-cloudflare-tunnel.md` "Superseded by ADR 19", `docs/decisions/24-edge-ingress-appliance.md` Decision bullet 4, `CHANGELOG.md` (2026-07 `cloudflared` entry), `docs/runbooks/20-deploy-zot.md` (traffic flow line).
- **Existing mitigation**: none effective - the in-document banner only fixes the document, not the five artefacts that point at it.

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
- **What**: 33 open issues. Ten carry **no label** (#13, #16, #34, #36, #39, #43, #44, #48, #104, #107). Three are superseded by accepted decisions but remain open: #54 (ML110 NAS) and #62 (ML110 Phase 2) after ADR 29 made the ML110 a retiring node, and #75 (monitoring reconciliation) after ADR 27 settled it. Eleven have had no activity since June/July (#3, #4, #13, #16, #33, #34, #36, #38, #39, #43, #48). Three titles still carry `(feat)`/`(research)` prefixes from before the naming rule (#3, #4, #57, #58).
- **Why it matters here**: this is the one workstream the board rule does **not** cover, and the only place the debt was recorded is a PR body (PR #110 Notes names the dormant sweep by issue number) - which is not a durable backlog artefact and will not be re-read.
- **Severity**: **Medium**
- **Evidence**: `list_issues` (open, 33); PR #110 Notes ("Deliberately outside this PR: ... the dormant-issue backlog sweep (#16, #34, #36, #38, #39, #43, #48, #53, #57, #58)"); `docs/overview.md` "Not Scheduled" (covers only #13, #3, #4).
- **Existing mitigation**: partial - the board parks three dormant items and the CHANGELOG records `#94` as shipped-and-removed.

### 3.5 No automated verification of any kind
- **What**: `.github/` contains only `copilot-instructions.md`, `prompts/` and `skills/` - there is no `workflows/` directory. `AGENTS.md` states three verification rules (ansible-lint before commit, live `--diff` playbook run before merge, post-merge re-run), and the repo ships smoke tests (`docker/opencode-base/tests/verify-base.sh`, `docker/opencode-homelab/tests/verify-homelab.sh`, `docker/opencode-prospera/tests/verify-prospera.sh`) - but nothing executes any of them. Bicep validation is a manual MCP step; Markdown link integrity is unchecked (see 3.6).
- **Why it matters here**: the repo's whole quality story rests on a single operator remembering three manual steps across a spare-time schedule, and the two failures this audit found in *code* (hardcoded hostnames, runbook-08-style index gaps) are exactly the class a 20-line workflow catches.
- **Severity**: **High** (structural; it is the multiplier on every other finding)
- **Evidence**: `.github/` listing; `AGENTS.md` "Ansible Verification"; `docker/*/tests/`.
- **Existing mitigation**: documented manual process + PR-time Copilot review.

### 3.6 Documentation link rot and stale cross-references
- **What**: `docs/opencode-customization/README.md` links runbooks and ADRs with paths relative to its own folder (`runbooks/17-...`, `decisions/16-...`) but no such subfolders exist (`../runbooks/`, `../decisions/` would resolve) - 6 broken links. ADR 10 cites `260613-backup-strategy-restic-blob.md`, a filename that does not exist. ADR 13 cites `research/15-vps-selection.md` from inside `docs/decisions/` (should be `../research/`). `docs/runbooks/README.md` omits any explanation for the missing runbook number 08 (verified: it was never tracked).
- **Why it matters here**: the ADR/research/runbook cross-links are the primary navigation path for both the operator and the agent.
- **Severity**: **Low**
- **Evidence**: `docs/opencode-customization/README.md` (runbook + ADR indexes); `docs/decisions/10-ansible-host-config.md` Decision/Scope bullet; `docs/decisions/13-cloudlab-staging.md` References; `git log --all -- 'docs/runbooks/08*'` (empty).
- **Existing mitigation**: none.

### 3.7 The `adr-authoring` skill contradicts the repo it governs
- **What**: the skill mandates `docs/decisions/YYMMDD-NN-kebab-case-title.md` filenames (no file in the repo uses that form) and ends with "**Commit directly to `main`** (per Homelab workflow)" - the exact opposite of the current branch -> PR rule in both instruction files. It also routes "writing research docs" to a "research-output skill" that does not exist (`skills/` holds `adr-authoring`, `fleet-connect`, `gemini-thread-summary`, `grill-me`).
- **Why it matters here**: skills are read by the agent as authoritative *rules*, so this is a Rule-vs-Rule conflict, not just stale prose. It is already acknowledged in PR #110's Notes as deliberately deferred.
- **Severity**: **Medium**
- **Evidence**: `.github/skills/adr-authoring/SKILL.md` "File naming" + "Commit conventions" + description; actual filenames `docs/decisions/01-*.md` .. `31-*.md`; `.github/skills/` listing.
- **Existing mitigation**: known (PR #110 Notes) but unscheduled.

### 3.8 State-doc drift below the "move together" rule
- **What**: `docs/hardware.md` HA node Status reads "HA VM/LXC still pending (#68 / #85)" while `docs/overview.md` reports the NUT LXC 213 server side delivered ([#115]) and ADR 30 is Accepted on the same node. `docs/overview.md`'s topology diagram still places the OMV NAS at `192.168.2.210` and omits the Beetle NAS (`192.168.2.202`, listed in its own Nodes table) and the OPNsense router. Idea lifecycle statuses lag delivery: idea 04 is still "Implementing" though ADR 24 is Accepted and the `edge_host` role shipped, and idea 01c is "Planned" though ADR 29 is Accepted and the unit is in hand. The two legends also reuse the same glyphs with different meanings (`docs/overview.md` uses a running icon for ✅; `docs/ideas/README.md` uses it for "Done").
- **Why it matters here**: the "overview + hardware move together" rule works at the node-row level but not at the sub-node (guest/LXC) or diagram level, which is where the truth now lives.
- **Severity**: **Low**
- **Evidence**: `docs/hardware.md` HA "Status" row; `docs/overview.md` Nodes table + Topology block + UPS row; `docs/ideas/README.md` rows 01c/04/05; both legend lines.
- **Existing mitigation**: Copilot review catches overview-vs-hardware mismatches at the node-row level (repo memory).

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

### 4.1 No CI gate
- **Missing**: any automated check. All verification is manual and unenforced.
- **Lightweight fix**: one workflow, three steps - (a) `ansible-lint` on changed role paths, (b) Bicep compile via the Bicep CLI/MCP on changed `bicep/**`, (c) a link check over `docs/**/*.md` (lychee or `markdown-link-check`). Add the three `docker/*/tests/verify-*.sh` as a matrix job if the images are to stay portable. No test framework, no coverage target.
- **Effort**: Low-Medium (one session, no Ansible/script changes).
- **Issue?** Yes - multi-session to tune the changed-path filters.

### 4.2 No automated currency check for the decision log and board
- **Missing**: nothing verifies ADR status values, index-title/filename parity, that a superseded ADR names its successor, or that a board row references a live issue. Findings 3.1, 3.2, 3.6 and 3.8 are all in this class.
- **Lightweight fix**: a `scripts/Test-HomelabDocs.ps1` that asserts (i) every `**Status:**` value is in the allowed set, (ii) every ADR row in `docs/decisions/README.md` links a file that exists and whose `#` title matches the row, (iii) every `Superseded by` target exists, (iv) every `#NNN` on the board resolves to an open issue. Wire it into the workflow from 4.1. This is the single highest-yield guard for this repo's failure mode.
- **Effort**: Low (one session, one script + a workflow step).
- **Issue?** Yes - pairs with 4.1.

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

1. **Retire the ADR 19 contradiction before the edge migration is built** - rename/retitle ADR 19 (or add an explicit "revised in place" title to the index row), correct ADR 08's supersession note, and fix ADR 24's "ADR 19 pattern applies" bullet to the plain-HTTP origin that `Caddyfile.j2` and runbook 20 actually implement. Files: `docs/decisions/19-cloudflare-tunnel-https-origin.md`, `docs/decisions/README.md`, `docs/decisions/08-remote-access-cloudflare-tunnel.md`, `docs/decisions/24-edge-ingress-appliance.md`.
2. **Add `.github/workflows/validate.yml`** - `ansible-lint` on changed roles, Bicep diagnostics on changed `bicep/**`, and a Markdown link check; this converts the repo's three honour-system rules into enforced gates and would have caught 3.1, 3.2 and 3.6.
3. **One doc-currency PR** - fix the `adr-authoring` skill (filename pattern, `main`-commit rule, missing skill reference), correct the stale statuses (ADR 02, 09, 25, 28) and idea rows (01c, 04), and parameterise/sanitise the domain (3.3).

---

## Summary table

| # | Finding | Type | Severity | Evidence |
|---|---|---|---|---|
| 3.1 | ADR 19's decision contradicts its filename, index row, ADR 08, ADR 24 and the CHANGELOG | Antipattern | High | `docs/decisions/19-*.md`, `decisions/README.md` row 19, ADR 08 "Superseded by", ADR 24 Decision, CHANGELOG 2026-07 |
| 3.2 | Stale / out-of-set ADR statuses (02, 09, 25, 28) | Antipattern | Medium | `docs/decisions/README.md`, ADR 25 promotion paragraph, ADR 28 Status line |
| 3.3 | Real domain `cloud5.ovh` committed in 15 files; `Caddyfile.j2` hostnames unparameterised | Antipattern | Medium | `.github/copilot-instructions.md` Security; `Caddyfile.j2` L1/5/9 vs `docker_services/defaults/main.yml` |
| 3.4 | 33 open issues: 10 unlabelled, 3 superseded-but-open, 11 dormant | Antipattern | Medium | `list_issues`; PR #110 Notes |
| 3.5 | No CI at all; lint/tests played but never enforced | Antipattern | High | `.github/` has no `workflows/`; `AGENTS.md` Ansible Verification; `docker/*/tests/` |
| 3.6 | Broken relative links + a non-existent ADR-10 filename; runbook 08 gap | Antipattern | Low | `docs/opencode-customization/README.md`; `docs/decisions/10-*.md`; `git log -- docs/runbooks/08*` |
| 3.7 | `adr-authoring` skill mandates a dead filename pattern and "commit directly to `main`" | Antipattern | Medium | `.github/skills/adr-authoring/SKILL.md` |
| 3.8 | `hardware.md` HA status vs `overview.md`; topology omits Beetle/OPNsense; idea statuses lag; legend clash | Antipattern | Low | `docs/hardware.md` HA Status; `docs/overview.md` Topology; `docs/ideas/README.md` rows 01c/04 |
| 3.9 | 5 concurrent "In progress" rows; 5 merged head branches on the remote | Antipattern | Low | `docs/overview.md`; `git branch -r` |
| 3.10 | Documentation ceremony above the minimum for one person | Antipattern | Negligible | `docs/` tree; `CHANGELOG.md` |
| 4.1 | No CI gate | Gap | High / Low-Medium effort | `.github/` |
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
