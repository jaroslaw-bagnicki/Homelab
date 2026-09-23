---
name: Triage Next Item
description: "Triage the Homelab backlog and recommend the single next item to tackle, weighted by repo momentum. Read-only. Use when: what should I do next, backlog triage, pick the next item, weekly backlog review, triage the issues."
argument-hint: "Optional focus or constraint (e.g. 'one session max', 'monitoring area', 'docs-only') — leave empty for a full pass"
agent: plan
---

Triage the Homelab backlog and answer one question: **what should I pick up next?** Run it
weekly, or when the next move is unclear. "Next" means the best progress per session weighted
by what the repo is **already carrying** — not the oldest issue or the loudest title.

**Rules.** The tracker carries the candidates; the board and recent history carry the momentum —
issue bodies alone are neither. Cite every claim (path + section, `#NNN`, ADR/runbook); never
invent an issue, label, board row, or dependency. **Write nothing** — no commit, push, PR, file
write, or issue/label/board edit; the operator applies. Say so when the honest answer is
"finish X first". State the run date (`YYYY-MM-DD`), which the windows below depend on. A
constraint supplied with the invocation is a **hard filter**, applied *before* the momentum
rules, with excluded candidates named.

## Read — stop once every momentum rule can be evaluated

- **Open issues** (GitHub MCP, `jaroslaw-bagnicki/Homelab`) — the live candidate universe:
  every title, label, age, last activity, body. **This set runs ahead of the board**, which
  carries only what is ready to start, so absence from the board says nothing about priority.
- `docs/overview.md` — the state and sequencing layer *over* those issues: **What's Next**
  (In progress → Planned → Held) and **Not Scheduled**. Each **Next step** is the intended
  continuation; each "Waiting on" / "Parked because" is a gate.
- `CHANGELOG.md` (current + previous month) and ~15 recently merged PRs — which workstreams
  are alive.
- Shortlisted candidates only: governing ADR/runbook/research; `docs/hardware.md` if gated.

**Issues win on existence, recency and scope; the board wins on intent** — execution order,
WIP state, gating. Read the board as a view that lags the tracker, never as the list of what
exists. Rules 1 and 7 need merged-PR history and issue ages, not just the board and CHANGELOG.

## Momentum rules — in order

| # | Rule | Effect |
|---|---|---|
| 1 | **Finish beats start** | Already **In progress**, or predecessor merged within two weeks, outranks any new start — unless a live blocker |
| 2 | **Warm context wins ties** | Prefer work adjacent to the newest CHANGELOG entries and merged PRs: host provisioned, role written, credentials loaded |
| 3 | **Prefer what unblocks others** | Name it; freeing two board rows beats freeing none |
| 4 | **Cheap wins when close** | ⭐ over ⭐⭐ — a merged PR sustains momentum better than a long-lived branch |
| 5 | **Respect the WIP cap** | One operator; with ~3 rows already In progress, recommend finishing or parking one, naming **Held** (gated, known start) vs **Not Scheduled** (no start date) |
| 6 | **Never pick gated work** | **Held** / **Not Scheduled** rows are out until their "Waiting on" / "Parked because" clears; say whether the gate is open. An issue with no board row is not gated — judge it on its own body |
| 7 | **Dormant work needs a reason to wake** | 6+ weeks untouched qualifies only if it now unblocks something, its gate cleared, or it is superseded and should be closed |

Effort is the board's scale: ⭐ one session · ⭐⭐ a few · ⭐⭐⭐ multi-week or hardware-gated.

## Triage pass — capped

**1. Board ↔ tracker reconciliation.** Compare every "What's Next" row against the tracker;
report by row name with `#NNN`: refs **closed** while the row remains (the completing PR should
have removed it) · a **Next step** already delivered (check CHANGELOG and merged PRs) · state
drift — In progress with no issue, **Planned** already underway, a **Held** gate that has
cleared, **Not Scheduled** with recent activity. Then the reverse: ready-to-start issues with
no row.

**2. Hygiene.** One line each, reusing the `docs/reports/*-quality-assessment.md` findings
rather than re-deriving an audit: unlabelled issue or `(type)`-prefixed title · superseded by a
settled ADR but still open · stale (6+ weeks) or duplicate · `overview.md` and `hardware.md`
disagreeing on a node's status.

## Output — chat only, tight

Open with the run date and any constraint applied.

1. **Pick** — one item, ≤3 bullets: *why now* (deciding rule + evidence), **first concrete
   step**, refs (`#NNN` + governing ADR/runbook), effort, what it unblocks.
2. **Runners-up** — ≤2, one line each, naming the rule that disqualified them.
3. **Triage findings** — `# | Finding | Suggested fix`, ≤5 rows, reconciliation first; each
   with `#NNN` or a path.
4. **Left alone** — one line on the strongest candidate not picked, and why.

No praise, no framework theory, no option menu — one recommendation, one first step. If a
tool group is unavailable, say so in a line and work with what you can read.
