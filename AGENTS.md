# Homelab — Opencode Agent Instructions

Rules for **autonomous, delegated** agent sessions in this repo. Interactive
sessions under user supervision (e.g. GitHub Copilot Chat) use
`.github/copilot-instructions.md` instead — this file is for the agent when
operating on its own.

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
- Research docs: `homelab/research/` — numbered Markdown files (`01-*.md`, `02-*.md`, …).
  Useful for exploratory context, but ADRs in `docs/decisions/` supersede research
  docs once a direction is settled.
- Runbooks: `runbooks/` — implementation instructions and operational procedures
- Each area has a `README.md` as the index

## Git Workflow

- **GitHub repository**: `https://github.com/jaroslaw-bagnicki/Homelab` (owner: `jaroslaw-bagnicki`, repo: `Homelab`)
- **Always use GitHub MCP tools** for GitHub operations — never GitKraken MCP tools for GitHub
- **If a GitHub MCP tool call fails**, report the error to the user and do not attempt the operation via any other tool or CLI
- **Always commit directly to `main`** — no feature branches, no PRs
- **Commit message format**: `(type) description` with parentheses. Common types: `docs`, `feat`, `fix`, `chore`, `refactor`
- **Never rebase** unless explicitly asked
- **Never push** unless explicitly asked
- **Scope commits tightly** — one logical change per commit; do not bundle unrelated edits

## Security

- **NEVER commit credentials**: API keys, passwords, connection strings, tokens, or secrets
- **Use placeholders**: Replace credentials with `[REDACTED]`, `YOUR_API_KEY_HERE`, or environment variables
- **Scripts**: accept credentials as parameters or read from the environment — never hardcode
- **Review before commit**: always check for exposed credentials before committing
- **Sanitize real domain names** — replace any real personal domain (e.g. `my-domain.net`) with `example.com` in all documentation, configs, and code before committing. The repo is public.

## Azure Tooling

- **Command-line Azure access**: Always use **Azure PowerShell** (`Az` module) — never Azure CLI (`az`)
- Use `Az` PowerShell cmdlets (e.g., `Get-AzResourceGroup`, `New-AzResourceGroup`) in any generated scripts or commands
- **Bicep schema lookups**: use the `azure-mcp_bicepschema` MCP tool (`bicepschema_get` subcommand) — never `az bicep build` for schema checks
- For resource-type API versions, look up via the Bicep schema before writing any new resource declaration

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

## Autonomous Agent Behavior

- **Act decisively** on the task; do not pause for confirmation on routine, reversible work
- **Ask only when blocked or when a choice materially changes the deliverable** — use the question tool sparingly
- **Plan first for non-trivial work**: enter plan mode, gather context, present the plan, exit plan mode, then execute
- **Verify after changes** — run any documented lint, test, or typecheck command before declaring the task done
- **Commit when work is done** — completed work should land on `main` in scoped commits matching the repo convention; do not leave changes uncommitted
- **Surface findings as concise summaries** — short status with file paths and commit refs; not essays
- **Discover skills via the skill tool** — repo skills live under `.opencode/skills/` (symlinked to `.github/skills/`); load a skill only when its description matches the current task
- **Do not create issues proactively** — issue creation is reserved for multi-session work the user explicitly asks to track; for one-shot fixes or docs changes, a commit is enough
