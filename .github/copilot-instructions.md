# Homelab — Copilot Instructions

## Project Overview

**Homelab** is a personal hub for small, independent mini-projects. Each sub-folder is a self-contained project — research notes, experiments, configs, or small tools. Projects are added organically as new topics emerge.

| Folder | Description |
|---|---|
| `homelab/` | Home lab server research — hardware, OS, local LLM/agent stack |

## Documentation

- Research docs: `homelab/research/` — numbered Markdown files (`01-*.md`, `02-*.md`, …)
- Each area has a `README.md` as the index
- For research output structure, use the `research-output` skill — see `.github/skills/research-output/SKILL.md` for the required structure

## Issue Tracking

- **Task tracking**: GitHub Issues (`https://github.com/jaroslaw-bagnicki/Homelab/issues`)
- **When creating an issue**: use a clear title, add relevant labels, and include a brief **Why / What** description
- **Reference issues in commits**: use `#NNN` in commit messages to link them automatically — use `Closes #NNN` to auto-close on merge commit

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

## Azure Tooling

- **Command-line Azure access**: Always use **Azure PowerShell** (`Az` module) — never Azure CLI (`az`)
- Use `Az` PowerShell cmdlets (e.g., `Get-AzResourceGroup`, `New-AzResourceGroup`) in any generated scripts or commands
- **Bicep validation**: Use the `mcp_bicep_get_bicep_file_diagnostics` MCP tool to validate Bicep files — never `az bicep build`
- **If validation returns errors**, fix all reported issues and re-validate before committing the file

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
