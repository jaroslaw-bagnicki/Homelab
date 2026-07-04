# Adopt OpenCode for Agentic Homelab Development

**Date:** 2026-06-28  
**Status:** Implemented

---

## Context

The Homelab project needs an agentic AI assistant that can act on the repo:
read code, run scripts, call Azure / GitHub / Ansible tools, drive multi-step
workflows across PRs, Bicep, and Ansible playbooks. Two predecessor
evaluations were rejected:

- **ADR 15 — Copilot Desktop agentic dev environment (Deferred, 2026-06-25).**
  Failed on three blockers: no Dev Container support, global-only MCP configs
  (not version-controlled per repo), and no Codespaces compatibility.
- **Issue #17 — VS Code Agents Window (Closed).** Doesn't work in Codespaces
  because it requires a dev tunnel from desktop VS Code.

Both evaluations were documented as complete with no path forward on the
two blockers above.

OpenCode (`opencode.ai`) is a third alternative already installed at
`/home/vscode/.opencode/bin/opencode` in this Codespace. Early evaluation
(comment 1 on issue #19, 2026-06-25) found it cleared the two critical
predecessor blockers: it runs inside the existing Dev Container, and its
config (`opencode.json` at repo root) is per-project and version-controlled.

---

## Decision

**Adopt OpenCode** as the primary agentic development tool for Homelab work
done in GitHub Codespaces. The evaluation is complete; this ADR formally
records the decision and the supporting infrastructure shipped with it.

Three infrastructure pieces accompany this decision:

1. **Session persistence** — `setup-opencode-persist.ps1` symlinks the four
   OpenCode runtime data dirs into `/workspaces/.opencode/{share,state,config,cache}`
   on every container create. Without this, every Dev Container rebuild wipes
   the SQLite session DB (`opencode.db`), losing all chat history.
2. **Azure Blob backup** — `Backup-OpencodeData.ps1` tarballs the persisted
   data on demand to `homelabcloud5/opencode-backups/`. Reuses the existing
   `homelab-codespaces-sp` service principal from ADR 16, with one additional
   RBAC grant (`Storage Blob Data Contributor` on the storage account).
3. **Hardened migration path** — the persistence script uses atomic staging
   (`<target>.staging` → `Rename-Item` → `rm` original) plus the SQLite
   `Connection.backup()` API for `opencode.db`. Eliminates the data-loss race
   that bit us during the initial deploy (the incident documented in
   runbook 15).

Out of scope for this evaluation:

- **Background automations / scheduled agent tasks.** Not investigated in
  this round. May be revisited as a follow-up issue if a use case surfaces.
- **Cross-machine session sharing.** Symlinks are local to one Codespace's
  `/workspaces` mount. Cross-machine would require the SQLite-over-Fileshare
  architecture (rejected in runbook 15 § Alternatives).

---

## Consequences

### Positive

- **Survives Dev Container rebuilds.** OpenCode sessions persist via symlinks
  to the Codespaces persistent disk. Verification procedure in runbook 15.
- **Per-project, version-controlled config.** `opencode.json` is committed,
  reproducible across machines, reviewable in PRs. Solves ADR 15's blocker.
- **MCP support.** Both GitHub MCP (remote HTTP, `GH_PAT` auth) and Azure MCP
  (local stdio, `AZURE_*` env vars from Codespaces secrets) are operational
  via `opencode.json`. Azure MCP authenticated via the Codespaces SP (ADR 16)
  with `Contributor` on `homelab-rg`.
- **Custom LLM providers.** DeepSeek (paid API) and MiniMax coding plan
  (subscription) are wired in `opencode.json`. Provider and model switching
  work at runtime via the OpenCode TUI.
- **Cross-device compatible.** Works identically in Codespaces, in a future
  local devcontainer on the homelab server, or in a fresh clone of the repo.
- **Reproducible environment.** Dev container (`devcontainer.json`) is
  unchanged; OpenCode install + extension were already in place.
- **No new infrastructure required for persistence.** Uses the existing
  `/workspaces` mount that Codespaces already provides.

### Negative

- **Single-Codespace scope for symlinks.** Two Codespaces on the same repo
  don't share sessions. Acceptable: the project's primary dev surface is one
  Codespace per developer per session.
- **Azure backup is manual.** `Backup-OpencodeData.ps1` runs on demand, no
  schedule. Auto-backup would need either a Codespaces lifecycle hook (not
  available for arbitrary user scripts) or a GitHub Actions cron (added
  complexity, separate decision).
- **No retention policy on `homelabcloud5/opencode-backups`.** Tarballs
  accumulate indefinitely. At ~17 MB per snapshot and ~$0.02/GB/mo, cost is
  trivial for months of accumulation; manual cleanup if needed.
- **Codespaces SP credentials gate the backup path.** Rotating the SP secret
  (per ADR 16) requires updating the Codespaces repo secret and rebuilding
  the Codespace for the new value to flow through.
- **Migration had a real failure mode during the initial deploy.** First-run
  `tar | tar` pipe was interrupted mid-stream; original DB was deleted before
  extraction completed; OpenCode created a fresh empty DB; recovery required
  merging 16 sessions from the emergency-backup tar with 1 session from the
  fresh DB. Hardened script (atomic staging + SQLite backup API) addresses
  the class; emergency tarballs are still on `/workspaces/` as a safety net.

### Alternatives Considered

- **Copilot Desktop** — rejected per ADR 15 (Deferred): no Dev Container
  support, global-only MCP configs, no Codespaces compatibility. Status
  unchanged by this ADR.
- **VS Code Agents Window** — rejected per issue #17 (Closed): requires dev
  tunnel from desktop VS Code, doesn't work in Codespaces.
- **Continue without an agentic tool** — rejected: blocks the Hermes Agent
  workflow and any other agent-driven development on the repo. The project
  is past "tinker" phase and into "exercise the platform" phase (per
  README.md goal: *Experiment with AI workloads*).
- **Adopt OpenCode without persistence infrastructure** — rejected: every
  Dev Container rebuild would wipe sessions, making evaluation painful and
  any multi-step agent work effectively impossible across rebuilds. The
  persistence/backup infrastructure is what makes the adoption viable.
- **Adopt OpenCode with Azure Fileshare cross-machine sync instead of
  symlinks** — rejected per runbook 15 § Alternatives Considered:
  SQLite-over-SMB has known consistency issues, and the cross-machine
  scope doesn't match the project's "one Codespace per session" usage.

---

## Implementation Notes

### Files shipped

| Commit | File | Change |
|---|---|---|
| `4914edd` | `.devcontainer/scripts/setup-opencode-persist.ps1` | NEW — symlink persistence + idempotent migration |
| `4914edd` | `.devcontainer/devcontainer.json` | EDIT — prepended `setup-opencode-persist.ps1` to `postCreateCommand` |
| `4914edd` | `scripts/Backup-OpencodeData.ps1` | NEW — manual Azure Blob upload |
| `4914edd` | `scripts/Add-HomelabOpencodeBackupStorage.ps1` | NEW — one-time deploy: container + SP role grant |
| `4914edd` | `docs/runbooks/14-gh-codespaces-sp-for-homelab.md` | EDIT — added § Additional role for storage data-plane |
| `4914edd` | `docs/runbooks/15-opencode-session-persistence.md` | NEW — full setup + verification + backup + restore |
| `4914edd` | `README.md` | EDIT — added "Opencode adoption" row to "What's Done" |
| `ab4ce66` | `opencode.json` | EDIT — renamed MCP key `azure` → `azure-mcp` |
| `ab4ce66` | `docs/runbooks/14-gh-codespaces-sp-for-homelab.md` | EDIT — synced `mcp.azure` reference |
| `e83cbca` | `.devcontainer/scripts/setup-opencode-persist.ps1` | EDIT — hardened: atomic staging + SQLite backup API |
| `f6a4c6f` | `docs/runbooks/14-gh-codespaces-sp-for-homelab.md` | EDIT — synced "Files touched" table with MCP rename |
| `a590272` | `docs/runbooks/README.md` | EDIT — added runbook 15 to index |
| `a590272` | `docs/runbooks/12-codespaces-devcontainer.md` | EDIT — cross-linked to OpenCode persistence |
| `a590272` | `docs/runbooks/15-opencode-session-persistence.md` | EDIT — added "Test the durability claim" procedure |

### PR

[PR #20 — feat/19-evaluate-opencode](https://github.com/jaroslaw-bagnicki/Homelab/pull/20)

### Verification procedure (recommended, not blocking)

Runbook 15 § "Test the durability claim" — 5-step round-trip:
send a marker message → `sqlite3` query to confirm DB has it →
`Dev Containers: Rebuild Container` → reopen OpenCode → confirm marker
session still present. Confirms the symlink persistence works end-to-end
across the exact scenario that this ADR's persistence layer was built to
survive.

### References

- Issue #19 — Evaluate OpenCode for agentic Homelab development (this ADR's origin)
- ADR 15 — Copilot Desktop agentic dev environment (Deferred — predecessor)
- ADR 16 — GH Codespaces Service Principal for Homelab (provides the SP for Azure MCP auth + Blob backup)
- Issue #17 — VS Code Agents Window evaluation (Closed — predecessor)
- Issue #13 — Restic backup to Azure Blob (creates `homelabcloud5` — backup path dependency)
- PR #20 — feat/19-evaluate-opencode (ships this ADR)
- Runbook 14 — GH Codespaces Service Principal for Homelab
- Runbook 15 — OpenCode session persistence + backup in Codespaces (operational doc)
- Research 14 — Backup cost comparison (Restic vs Azure Backup MARS, justifies Restic)
- Research 16 — GitHub Codespaces & Dev Containers (Codespaces architecture context)
