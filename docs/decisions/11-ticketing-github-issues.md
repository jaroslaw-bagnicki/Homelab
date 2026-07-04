# Ticketing System — GitHub Issues

**Date:** 2026-06-13  
**Status:** Implemented

---

## Context

The Homelab project needed a lightweight way to track features, bugs, and ideas
across sessions. Options ranged from full-featured project management (Jira) to
no tracking at all.

Requirements:
- **Zero ceremony** — single-person hobby project, no sprints, no statuses
- **Zero cost** — the repo is public on GitHub, no budget for tooling
- **Low friction** — create an issue in seconds, close it in a commit
- **Commit integration** — auto-close issues from commit messages (`Closes #NNN`)
- **Co-exist with README** — the existing `README.md` progress table remains the
  public status board; issues are the backlog

## Decision

Adopt **GitHub Issues** as the project's ticketing system.

### Rejected Options

| Option | Verdict | Reason |
|---|---|---|
| **Jira** | ❌ Rejected | Overkill for a single-person hobby project; adds ceremony (statuses, transitions, workflows); separate login and context switch from the repo |
| **GitHub Projects** | ❌ Rejected | Kanban boards add visual overhead for a one-person, commit-to-main workflow; no meaningful columns to move cards through |
| **No system** | ❌ Rejected | Status quo, but no way to capture ideas for later or link commits to tracked items; ideas get lost between sessions |

### Workflow

1. Idea → create a GitHub issue (backlog)
2. Ready to start → add a row to `README.md` "What's Next"
3. Finished → move to "What's Done" with date + runbook link
4. Close the issue

Issues capture ideas and multi-session work. One-shot `(docs)` or `(chore)`
commits do not need issues. Ongoing research lives in `research/` docs, not
issues.

### Labels

- `enhancement` — new feature or capability
- `bug` — something broken
- `chore` — maintenance, tooling, infra
- `research` — investigation before implementation

## Consequences

- Commit messages can auto-close issues via `Closes #NNN` — traceability without
  ceremony
- The `README.md` progress table stays as the canonical status board; issues are
  purely a backlog, never a duplicate status tracker
- Zero additional cost or tooling — everything lives in the GitHub repo
- Easy to escalate later — if the project grows, GitHub Projects can be enabled
  on top of the same issues with zero migration
- The convention is documented in `.github/copilot-instructions.md` so the AI
  agent follows the same flow
