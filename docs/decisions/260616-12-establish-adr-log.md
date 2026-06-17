# Establish Lightweight ADR Log in MADR Format

**Date:** 2026-06-16  
**Status:** Implemented

---

## Context

The Homelab project accumulates design decisions across sessions — hardware
choices, OS decisions, container stack, networking, backup strategy, monitoring
approach, etc. Currently these decisions are embedded inside research documents
and runbooks with no indexed, standalone record of what was decided, when, why,
and what alternatives were considered.

Without a lightweight decision log, the project is at risk of:

- Re-debating settled questions in future sessions
- Losing the rationale behind past choices when context fades
- Having no canonical place to look up "why did we pick X over Y"
- Starving the AI agent of structured context — without ADRs, the agent has
  only research docs and runbooks to infer design rationale from, which are
  noisy, unstructured, and often omit trade-off reasoning

The [MADR](https://adr.github.io/madr/) format (Markdown Any Decision Records)
is a well-known lightweight ADR approach used successfully in the Prospera
project in this workspace.

## Decision

Adopt the MADR format for the Homelab project's decision log.

- Create `docs/decisions/` as the canonical location
- ADR filename pattern: `YYMMDD-kebab-case-title.md`
- Each ADR follows the Context → Decision → Consequences arc
- Status values: Proposed · Accepted · Implemented · Deferred · Superseded · Deprecated
- `docs/decisions/README.md` serves as the index/log table (newest first)
- `docs/decisions/TEMPLATE.md` provides a ready-to-copy template
- A SKILL file (`.github/skills/adr-authoring/SKILL.md`) captures this convention
  for the AI agent

## Consequences

- Future decisions have a discoverable, indexed home — no more hunting through
  research docs for settled answers
- The AI agent gets structured, high-signal context — ADRs directly answer
  "why was X chosen?" without needing to parse verbose research documents
- Decision log is plain Markdown — no tooling dependency, works in any editor
- Lightweight overhead — one file per decision, one row added to README
- No backfilling of past decisions — only forward-looking records from this
  point forward

### Alternatives Considered

- **No formal logging** — rejected: exactly the problem we're solving
- **ADRs in the Prospera repo only** — rejected: Homelab has independent
  decisions (hardware, OS, local infra) unrelated to Prospera
- **YAML/structured format** — rejected: Markdown is easier to read, write, and
  diff in pull requests
