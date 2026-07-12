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
- **Never rebase** unless explicitly asked (the rebase step in [Worktree Workflow](#worktree-workflow) merge-via-PR is the standard carve-out)
- **Never push** unless explicitly asked
- **Scope commits tightly** — one logical change per commit; do not bundle unrelated edits

## Workloads as self-contained recipes

Each workload in this repository is its own self-contained recipe, runnable independently via `ansible-playbook ansible/<workload>/<workload>.yml`. The base `ansible/playbooks/playbook.yml` does NOT list workloads.

A new workload is added by:

1. Creating `ansible/<workload>/` containing the playbook entrypoint, role recipes, and an ansible-side README.
2. Adding a row to the index table in `docs/workloads.md`.
3. Adding a row to `README.md` ("What's Next" or "What's Done").
4. Optionally: a runbook at `docs/runbooks/NN-deploy-<workload>.md` for operational steps.

Workloads do not import each other. Workloads do not declare shared pre_tasks in the base playbook. Idempotent declarations inside a workload's roles are acceptable (e.g. networks — declare in the role and in the base playbook pre_tasks; first writer wins).

## Worktree Workflow

Autonomous sessions always work on a **feature branch inside a git worktree** — `main` stays for merged, reviewed work only, and multiple agents can run in parallel without contention.

### Sync `main` with remote (first, every session)

1. `git fetch origin`
2. From the primary checkout, on `main`: `git merge --ff-only origin/main`
3. If FF fails (unpushed local commits or diverged history): stop and report to the user — never force, rebase, or commit on `main` autonomously

If the session was started in a worktree on a feature branch, switch back to the primary checkout (`cd ..` or use the `workdir` parameter) before syncing.

### Detect / setup

```
git rev-parse --show-toplevel        # current worktree path
git rev-parse --abbrev-ref HEAD      # current branch
```

- If `HEAD` is `main` AND path matches the primary checkout → not set up:

  ```
  git worktree add ../Homelab-<short-topic> -b <type>/<short-kebab-topic>
  ```

  Use the bash tool's `workdir` parameter for all subsequent commands inside the new worktree.

- Otherwise → already in a worktree on a feature branch, skip setup

### Branch naming

`<type>/<short-kebab-topic>` matching the eventual commit `type`. Examples: `docs/add-adr-19`, `feat/local-llm-stack`, `fix/ansible-vps-timeout`.

### Merge via PR (default path)

Merges always go through a pull request — the agent never merges to `main` locally unless explicitly asked.

1. In the worktree: `git fetch origin && git rebase origin/main` — resolve any conflicts
2. Ask the user for push permission: "Branch `<branch>` is ready. Push and open a PR?"
3. After confirmation: `git push -u origin <branch>`, then open the PR via GitHub MCP tools (`create_pull_request`)
4. **Stop.** The human reviews and merges via the GitHub UI — the agent never merges the PR itself
5. After the PR is merged, clean up in the primary checkout: `git pull --ff-only origin main`, then `git worktree remove ../Homelab-<short-topic>` and `git branch -d <branch>`

### Local merge (only on explicit ask)

Phrases like "merge locally", "fast-forward to main", "skip the PR", "do it directly". The agent may then `git merge --ff-only <branch>` from the primary checkout. Still confirm before executing — this is a privileged operation.

### Worktree cleanup — only after merge

Never remove a worktree or delete its branch while the branch is unmerged. Cleanup happens only after the PR is merged (default path) or after the local merge completes (explicit-ask path).

### Exceptions to the worktree rule

Work on `main` directly only when the user says so ("commit to main", "no worktree", "skip the worktree step", etc). When in doubt, use a worktree — cleanup is trivial.

## PR Review Remarks Workflow

When asked to process PR review remarks, follow this human-in-the-loop flow:

1. Fetch all review comments from the PR using GitHub MCP tools (`pull_request_read` with `get_review_comments`)
2. Present a resolution proposal as a Markdown table with columns: `#`, `Remark`, `Resolution`
3. **Wait for user confirmation** before applying any changes
4. Apply only the accepted resolutions; commit and push (still on the feature branch)
5. Reply to each review thread via GitHub MCP tools (`add_reply_to_pull_request_comment`) with the resolution taken (accepted or rejected with reason)

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
- **Ask only when blocked, when a choice materially changes the deliverable, OR before any action that could corrupt shared state** — force-push, hard-reset of a published branch, deleting an unmerged branch/worktree, dropping shared data, running destructive migrations, etc. Confirm first, then proceed
- **Plan first for non-trivial work**: enter plan mode, gather context, present the plan, exit plan mode, then execute
- **Verify after changes** — run any documented lint, test, or typecheck command before declaring the task done
- **Commit when work is done** — completed work lands on the feature branch in scoped commits matching the repo convention; do not leave changes uncommitted
- **Surface findings as concise summaries** — short status with file paths and commit refs; not essays
- **Discover skills via the skill tool** — repo skills live under `.opencode/skills/` (symlinked to `.github/skills/`); load a skill only when its description matches the current task
- **Do not create issues proactively** — issue creation is reserved for multi-session work the user explicitly asks to track; for one-shot fixes or docs changes, a commit is enough
- **Never merge a PR, locally or remotely** — opening a PR is the final step of the agent's work; the human reviews and merges via the GitHub UI. This includes `merge_pull_request` calls, `git merge`, and any equivalent. Do not assume implicit merge permission even if the work appears "done". The same rule applies to PRs the agent authored across multiple sessions or that "look ready".

## Plan → Build Transition

The boundary between planning (read-only) and implementation (build) must be clear:

- **Step-by-step plan acceptance.** Present one plan step at a time. Do not move to the next step until the user accepts the current one. Never present multiple steps in one message unless asked.
- **Concept elaboration.** Define domain terms on first use (TLS SNI, Origin CA, CF edge, apex, SAN, Strict SSL, etc.) — one sentence, plain language. If the user asks "what is X?", stop and explain before continuing.
- **One recommendation, not option menus.** Pick the best approach and recommend it with a brief rationale. Only offer multiple options when the user must make a genuine tradeoff.
- **No live/direct changes during plan phase.** All implementation happens after the plan is fully accepted. Do not edit the live VPS, services, or infrastructure while the plan is still being discussed. Live edits during planning create unreproducible drift.

## Ansible Verification

- **ansible-lint before commit.** Run `ansible-lint ansible/roles/<role>/` on every changed role before committing. Lint failures are fatal and must be resolved.
- **Live playbook test before merge.** For non-trivial Ansible changes, run `ansible-playbook playbook.yml --diff` against the target host before opening the PR. Bugs in tasks (idempotency, output parsing, module parameters) only surface at runtime.
- **Post-merge deployment.** After the PR is merged, re-run the playbook to ensure the live host matches the merged code.
- **Pre-flight: fix world-writable workspace.** If the dev container workspace is world-writable (default), Ansible refuses to read `ansible.cfg`. Run `chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible` before `ansible-playbook`.
- **Never commit `ansible/ansible.log`.** The file is `.gitignore`'d but may have been tracked before. Untrack it with `git rm --cached ansible/ansible.log` if it appears in `git status`.
