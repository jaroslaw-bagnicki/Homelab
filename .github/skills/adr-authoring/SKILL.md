---
name: adr-authoring
description: >-
  Authoring and maintaining Architecture Decision Records (ADRs) in MADR format
  for the Homelab project. ADRs serve a dual purpose: (1) human-readable
  decision log, and (2) structured, high-signal context for the AI agent —
  directly answering "why was X chosen?" without requiring the agent to parse
  verbose research documents.
  Covers filename convention, required sections, status values, README index
  maintenance, and commit conventions.
  USE FOR: creating a new ADR, updating an existing ADR, reviewing an ADR,
  deciding whether a decision warrants an ADR, fixing a malformed ADR.
  DO NOT USE FOR: writing research docs (use research-output skill), writing
  runbooks (use runbook format), documenting standard operating procedures.
when:
  - user asks to "record a decision", "write an ADR", "log a decision"
  - user mentions "MADR", "architecture decision", "decision record"
  - a design decision with alternatives was made that has lasting consequences
  - ongoing research is resolving into a settled direction
---

# ADR Authoring — MADR Format

Architecture Decision Records (ADRs) capture significant decisions with lasting
consequences. Follow the [MADR](https://adr.github.io/madr/) (Markdown Any Decision
Records) lightweight format.

ADRs serve a **dual purpose**:
1. **Human decision log** — indexed reference for the project maintainer
2. **Agent context** — structured, high-signal input for the AI coding agent.
   Every ADR directly answers "why was X chosen?" so the agent can make
   informed follow-up recommendations without needing to dig through verbose
   research documents or infer rationale from code alone.

---

## When to write an ADR

Write an ADR when a decision:

- Has **lasting consequences** — will affect future choices or be hard to reverse
- Involves **trade-offs between alternatives** — not a trivial or obvious choice
- Has **cost, complexity, or risk implications** — hosting choice, tool adoption,
  architecture pattern, security model
- Is worth **referencing from future research docs, runbooks, or issues**
- Provides **context for the AI agent** — ADRs directly answer "why" questions
  that the agent needs for informed, context-aware suggestions

**No ADR needed for:** standard operating procedures, one-shot configuration tweaks,
tool version bumps, typos or formatting fixes.

---

## File naming

```
docs/decisions/YYMMDD-NN-kebab-case-title.md
```

- `YYMMDD` — date the decision was made (e.g. `260616`)
- `NN` — globally sequential number (01, 02, …) across all ADRs, assigned chronologically from oldest to newest
- `kebab-case-title` — short, descriptive title

**Example:** `260616-12-establish-adr-log.md`

---

## Required sections

Every ADR must contain these sections in order:

```markdown
# Title — Short, descriptive name

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Implemented | Deferred | Superseded | Deprecated

---

## Context

What prompted the decision? What constraints, assumptions, or prior analyses
inform it? Keep it brief — link to research docs for detail.

## Decision

What was decided. State the outcome clearly: "Adopt X for Y because of Z."

## Consequences

Bullet-list the implications — both positive and negative. What becomes easier?
What becomes harder? What does this decision commit the project to?

### Alternatives Considered

Optional section listing rejected options and why. One paragraph per alternative.
```

The **Context → Decision → Consequences** arc is mandatory.
`### Alternatives Considered` is strongly recommended but not required for
trivial trade-offs.

---

## Status values

| Status | Meaning |
|--------|---------|
| Proposed | Draft, under discussion, not yet settled |
| Accepted | Decision agreed but not yet implemented |
| Implemented | Decision has been carried out |
| Deferred | Decision postponed — revisit later |
| Superseded | Replaced by a later ADR |
| Deprecated | No longer recommended |

---

## README index

Every new ADR must be registered in `docs/decisions/README.md` as a new row
at the **top** of the decision log table (newest first) — in the same commit
that creates the ADR file.

---

## Commit conventions

- Commit message: `(docs) Add ADR: <title>`
- Include the ADR file AND the README index update in the same commit
- Commit directly to `main` (per Homelab workflow)

---

## Example: minimal ADR

```markdown
# Use Cloudflare Tunnel for Inbound Access

**Date:** 2026-06-16
**Status:** Accepted

---

## Context

The homelab server is behind a CGNAT ISP with no public IPv4. Direct port
forwarding is impossible. A tunnel solution is needed to expose services.

## Decision

Use Cloudflare Tunnel (cloudflared) instead of Tailscale Funnel or Ngrok.
Cloudflare Tunnel integrates with the existing DNS setup (Caddy + Cloudflare)
and provides access control, DDoS protection, and no per-tunnel cost.

## Consequences

- No open inbound ports on the homelab — good security posture
- All traffic routes through Cloudflare — single point of trust
- Free tier covers the expected light workload
- Adds Cloudflare as a dependency — tunnel config needed per service

### Alternatives Considered

- **Tailscale Funnel**: simpler ACL model, but requires Tailscale on every
  client device and doesn't integrate with the existing Caddy setup.
- **Ngrok**: per-connection rate limits on free tier and no DNS integration.
```
