# Homelab — Copilot Instructions

## Project Overview

**Homelab** is a personal hub for small, independent mini-projects. Each sub-folder is a self-contained project — research notes, experiments, configs, or small tools. Projects are added organically as new topics emerge.

| Folder | Description |
|---|---|
| `homelab/` | Home lab server research — hardware, OS, local LLM/agent stack |

## Dev Container

- **Default terminal shell is PowerShell (`pwsh`)** — run `.ps1` scripts directly (e.g. `.devcontainer/scripts/setup-azps.ps1`), never wrap with `pwsh -File`
- Run bash scripts with `bash script.sh` when needed

## Documentation

- **Decision log (`docs/decisions/`)** — **source of truth** for all settled design decisions.
  ADRs (Architecture Decision Records) record what was decided, when, why, and what
  alternatives were considered. When the agent needs to answer "why did we pick X
  over Y?", consult `docs/decisions/README.md` first — the decision log takes
  precedence over research docs and code comments for design rationale.
- Research docs: `docs/research/` — numbered Markdown files (`01-*.md`, `02-*.md`, …).
  Useful for exploratory context, but ADRs in `docs/decisions/` supersede research
  docs once a direction is settled.
- Runbooks: `runbooks/` — implementation instructions and operational procedures
- Each area has a `README.md` as the index
- **State docs stay current**: when a node or workload is added, removed, or changes
  status, update `docs/overview.md` (nodes/workloads view) and `docs/hardware.md`
  (per-node specs + network appliances) in the same change

## Issue Tracking

- **When to create an issue**: features, bugs, or ideas that span more than one session
- **When NOT to create an issue**: one-shot `(docs)` or `(chore)` commits, ongoing research (use `research/` docs for that)
- **When creating an issue**: use a clear title with **no `(type)` prefix** (e.g. not `(feat) …`) — the **label** conveys the type. Add relevant labels and a brief **Why / What** description
- **PR titles**: same rule — no `(type)` prefix in the title; use labels to convey the type (the `(type)` prefix convention applies to **commit messages only**)
- **PR descriptions**: do **not** use the **Why / What / How (WWH)** format — that is **reserved for GitHub Issues only**. PR descriptions are a plain summary of the **Changes** (and any **Notes**) with no WWH headings
- **Reference issues**: plain `#NNN` mentions link a commit/PR to an issue but do **not** auto-close it. To auto-close on merge, add `Closes #NNN` to the **PR description** or to a commit that is merged into `main` (GitHub evaluates the keyword at merge time; editing a merged PR afterwards won't close the issue)
- **Labels**: `enhancement` (new feature), `bug` (broken), `chore` (maintenance/tooling), `research` (investigation)
- **`docs/overview.md` "What's Next" = public status board** — shows what's planned or actively being worked on. Only items that are **planned** or **in progress** belong here.
- **Issues = the backlog** — capture ideas, bugs, and multi-session work that isn't in the overview table yet. An issue becomes a `docs/overview.md` "What's Next" row when you're ready to start it.
- **Typical flow**: idea → issue → move to `docs/overview.md` "What's Next" when starting → on completion add an entry to `CHANGELOG.md` (with runbook/ADR links) → close the issue
- When adding a completed entry to `CHANGELOG.md`, link the **runbook** (not the issue) — `[runbook](runbooks/NN-name.md)` — so the entry points to the implementation, not the ticket

## Git Workflow

- **GitHub repository**: `https://github.com/jaroslaw-bagnicki/Homelab` (owner: `jaroslaw-bagnicki`, repo: `Homelab`)
- **Always use GitHub MCP tools** for GitHub operations — never GitKraken MCP tools for GitHub
- **If a GitHub MCP tool call fails**, report the error to the user and do not attempt the operation via any other tool or CLI
- **Always commit directly to `main`** — no feature branches, no PRs
- **Commit message format**: `(type) description` with parentheses. Common types: `docs`, `feat`, `fix`, `chore`, `refactor`
- **Never rebase** unless explicitly asked

## Security

- **NEVER commit credentials**: API keys, passwords, connection strings, tokens, or secrets
- **Use placeholders**: Replace credentials with `[REDACTED]`, `YOUR_API_KEY_HERE`, or environment variables
- **Scripts**: accept credentials as parameters or read from the environment — never hardcode
- **Review before commit**: always check for exposed credentials before committing
- **Sanitize real domain names** — replace any real personal domain (e.g. `my-domain.net`) with `example.com` in all documentation, configs, and code before committing. The repo is public.

## Azure Tooling

- **Command-line Azure access**: Always use **Azure PowerShell** (`Az` module) — never Azure CLI (`az`)
- Use `Az` PowerShell cmdlets (e.g., `Get-AzResourceGroup`, `New-AzResourceGroup`) in any generated scripts or commands
- **Bicep validation**: Use the `mcp_bicep_get_bicep_file_diagnostics` MCP tool to validate Bicep files — never `az bicep build`
- **If validation returns errors**, fix all reported issues and re-validate before committing the file

## Review Remarks Workflow

When asked to process PR review remarks:

1. Fetch all review comments from the PR using the available GitHub MCP tools
2. Present a resolution proposal as a Markdown table with columns: `#`, `Remark`, `Resolution`
3. Wait for user confirmation before applying any changes
4. Apply only the accepted resolutions; commit and push
5. Reply to each review thread via GitHub MCP tools with the resolution taken (accepted or rejected with reason)

## Code Guidelines

### Bicep

- **Always use the latest stable (non-preview) API version** for every resource type — look it up via the provider catalog before writing any new resource declaration
- **No `@description` decorators** — use self-explanatory param names instead
- **Collocate resources by lifecycle** — group resources that are created/deleted together in the same module, not by resource type
- Use `parent:` property for child resources, never `/` in the `name`
- Use `existing` resource + symbolic `.id` instead of `resourceId()` or `reference()` functions

### PowerShell

- Keep scripts compact — no unnecessary comments or verbose documentation blocks
- Use typed `param()` blocks when the script accepts parameters; omit `param()` and `[CmdletBinding()]` entirely for parameter-less scripts
- Always use `Az` module cmdlets for Azure operations
- Prefer `Invoke-RestMethod` over `Invoke-WebRequest` for HTTP requests — use `-SkipHttpErrorCheck` when non-2xx responses are expected and should not throw
