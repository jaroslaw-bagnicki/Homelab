---
name: Triage Next Item
description: "Triage the Homelab backlog and recommend the single next item to tackle, weighted by repo momentum. Read-only. Use when: what should I do next, backlog triage, pick the next item, weekly backlog review, triage the issues."
argument-hint: "Optional focus or constraint (e.g. 'one session max', 'monitoring area', 'docs-only') — leave empty for a full pass"
agent: plan
---

Triage the Homelab backlog and answer one question: **what should I pick up next?** Run it
weekly, or when the next move is unclear. "Next" means the best progress per session weighted
by what the repo is **already carrying** — not the oldest issue or the loudest title.

**Rules.** The board and recent history — not issue bodies — are the momentum evidence. Cite
every claim (path + section, `#NNN`, ADR/runbook); never invent an issue, label, board row, or
dependency. **Write nothing** — no commit, push, PR, file write, or issue/label/board edit;
the operator applies. Say so when the honest answer is "finish X first". State the run date
(`YYYY-MM-DD`), which the windows below depend on. A constraint supplied with the invocation
is a **hard filter**, applied *before* the momentum rules, with excluded candidates named.

## Read — stop once every momentum rule can be evaluated

- `docs/overview.md` — the board: **What's Next** (In progress → Planned → Held) and **Not
  Scheduled**; each row's **Next step** is the intended continuation.
- `CHANGELOG.md` (current + previous month) and ~15 recently merged PRs (GitHub MCP,
  `jaroslaw-bagnicki/Homelab`) — which workstreams are alive.
- Open issues (GitHub MCP) — title, labels, age, last activity, body completeness.
- Shortlisted candidates only: governing ADR/runbook/research; `docs/hardware.md` if gated.

Rules 1 and 7 need merged-PR history and issue ages, not just the board and CHANGELOG.

## Momentum rules — in order

| # | Rule | Effect |
|---|---|---|
| 1 | **Finish beats start** | Already **In progress**, or predecessor merged within two weeks, outranks any new start — unless a live blocker |
| 2 | **Warm context wins ties** | Prefer work adjacent to the newest CHANGELOG entries and merged PRs: host provisioned, role written, credentials loaded |
| 3 | **Prefer what unblocks others** | Name it; freeing two board rows beats freeing none |
| 4 | **Cheap wins when close** | ⭐ over ⭐⭐ — a merged PR sustains momentum better than a long-lived branch |
| 5 | **Respect the WIP cap** | One operator; with ~3 rows already In progress, recommend finishing or parking one, naming **Held** (gated, known start) vs **Not Scheduled** (no start date) |
| 6 | **Never pick gated work** | **Held** / **Not Scheduled** rows are out until their "Waiting on" / "Parked because" clears; say whether the gate is open |
| 7 | **Dormant work needs a reason to wake** | 6+ weeks untouched qualifies only if it now unblocks something, its gate cleared, or it is superseded and should be closed |

Effort is the board's scale: ⭐ one session · ⭐⭐ a few · ⭐⭐⭐ multi-week or hardware-gated.

## Triage pass — capped

Note hygiene defects worth one line each, reusing the `docs/reports/*-quality-assessment.md`
findings rather than re-deriving an audit: unlabelled issue or `(type)`-prefixed title ·
superseded by a settled ADR but still open · stale (6+ weeks) or duplicate · board row with no
issue, or issue missing from the board · `overview.md` and `hardware.md` disagreeing on a
node's status.

## Output — chat only, tight

Open with the run date and any constraint applied.

1. **Pick** — one item, ≤3 bullets: *why now* (deciding rule + evidence), **first concrete
   step**, refs (`#NNN` + governing ADR/runbook), effort, what it unblocks.
2. **Runners-up** — ≤2, one line each, naming the rule that disqualified them.
3. **Triage findings** — `# | Finding | Suggested fix`, ≤5 rows, each with `#NNN` or a path.
4. **Left alone** — one line on the biggest board row not picked, and why.

No praise, no framework theory, no option menu — one recommendation, one first step. If a
tool group is unavailable, say so in a line and work with what you can read.
