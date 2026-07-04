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
- **Work on a feature branch in a worktree** — see [Worktree Workflow](#worktree-workflow) below; do not commit to `main` from an autonomous session
- **Commit message format**: `(type) description` with parentheses. Common types: `docs`, `feat`, `fix`, `chore`, `refactor`
- **Never rebase** unless explicitly asked (the rebase step in [Worktree Workflow](#worktree-workflow) merge-back is the standard carve-out)
- **Never push** unless explicitly asked
- **Scope commits tightly** — one logical change per commit; do not bundle unrelated edits

## Worktree Workflow

Autonomous sessions always work on a **feature branch inside a git worktree**. This isolates agent work from `main`, lets multiple agents run in parallel without contention, and keeps the primary checkout clean.

### Detect — am I already in a worktree?

Run first:

```
git rev-parse --show-toplevel        # absolute path of current worktree
git rev-parse --abbrev-ref HEAD      # current branch
```

- If `HEAD` is `main` AND the path matches the primary checkout → **not set up**, do the setup below
- Otherwise → already in a worktree on a feature branch, skip setup

### Setup (only if not already set up)

```
git worktree add ../Homelab-<short-topic> -b <type>/<short-kebab-topic>
```

Then run all subsequent commands inside the new worktree using the bash tool's `workdir` parameter (preferred) or by `cd`-ing into it. Verify with `pwd` and `git rev-parse --abbrev-ref HEAD`.

### Branch naming

- `<type>/<short-kebab-topic>` — match the commit `type` you will use. Examples: `docs/add-adr-19`, `feat/local-llm-stack`, `fix/ansible-vps-timeout`
- Keep topics short and specific

### Working model

- All file edits, commits, and pushes happen inside the worktree
- Multiple autonomous sessions can run in parallel, each on its own branch + worktree
- `main` is for merged, reviewed work only — never the working branch for an autonomous session

### Merge back to `main` (when user asks)

1. Inside the worktree: `git fetch origin && git rebase origin/main`
2. From the primary checkout: `git merge --ff-only <branch>`
3. `git worktree remove ../Homelab-<short-topic>`
4. `git branch -d <branch>`

### Exceptions — work on `main` directly only when user explicitly says so

Phrases like "commit to main", "no worktree", "skip the worktree step", "do it directly". When in doubt, use a worktree — cleanup cost is trivial.

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
- **Commit when work is done** — completed work lands on the feature branch in scoped commits matching the repo convention; do not leave changes uncommitted
- **Surface findings as concise summaries** — short status with file paths and commit refs; not essays
- **Discover skills via the skill tool** — repo skills live under `.opencode/skills/` (symlinked to `.github/skills/`); load a skill only when its description matches the current task
- **Do not create issues proactively** — issue creation is reserved for multi-session work the user explicitly asks to track; for one-shot fixes or docs changes, a commit is enough
