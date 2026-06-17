---
source: https://gemini.google.com/share/536c3e9635ff
model: Gemini 3.5 Flash
date: 2026-06-17
---

# GitHub Codespaces & Dev Containers for Homelab

## Topic

A discussion about using **GitHub Codespaces and Dev Containers** as a consistent,
browser-ready development environment for the Homelab project — eliminating local
toolchain drift and enabling instant onboarding for contributors.

The conversation covers what IDEs are available inside a Codespace, followed by
practical setup work: creating a `.devcontainer/devcontainer.json` with the right
tools, extensions, and MCP server configuration.

---

## Key Findings

### 1. IDE options in GitHub Codespaces

GitHub Codespaces supports four frontend modes, selectable via
`Settings → Codespaces → Editor preference`:

| Mode | Description |
|---|---|
| **Browser VS Code** (web-based) | Default — full VS Code in the browser tab |
| **Desktop VS Code** | Local VS Code connected to the cloud container via the GitHub Codespaces extension |
| **JetBrains IDE** (via JetBrains Gateway) | Thin-client mode — IntelliJ, PyCharm, WebStorm, Rider, GoLand, CLion |
| **Terminal / CLI** | Vim, Neovim, Emacs, Nano, or any CLI tool installed via `apt` or `devcontainer.json` |

### 2. Dev Container configuration

A `.devcontainer/devcontainer.json` has been created ([#10](https://github.com/jaroslaw-bagnicki/Homelab/issues/10))
with the following setup:

**Base image:** `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (matches the
homelab server OS)

**Features:**
| Feature | Purpose |
|---|---|
| `docker-outside-of-docker` | Docker CLI + Compose — bind-mounts the host Docker socket |
| `powershell` | PowerShell 7 — needed for Az module and repo PowerShell scripts |
| `azure-cli` | Azure CLI — for Bicep validation and ad-hoc queries |

**VS Code extensions:**
| Extension | Purpose |
|---|---|
| `ms-azuretools.vscode-bicep` | Bicep language support |
| `ms-vscode.powershell` | PowerShell IDE |
| `redhat.ansible` | Ansible playbook support |
| `bierner.markdown-mermaid` | Mermaid diagram rendering in Markdown preview |
| `ms-azuretools.vscode-docker` | Docker Explorer |
| `github.vscode-pull-request-github` | PR/issue integration |
| `github.copilot` | Copilot code completions |
| `github.copilot-chat` | Copilot Chat |
| `ms-azuretools.vscode-azure-mcp-server` | Azure MCP Server (resource mgmt, queries) |

**MCP server configuration** (`.vscode/mcp.json`):
| Server | Type | Endpoint |
|---|---|---|
| GitHub MCP | HTTP | `https://api.githubcopilot.com/mcp/` |
| Azure MCP | Provided via `ms-azuretools.vscode-azure-mcp-server` extension | N/A |

**Post-create command** installs:
- `ansible` — via apt
- `Az`, `Az.ConnectedMachine` PowerShell modules — via `Install-Module`
- `bicep` CLI — standalone binary from GitHub releases

### 3. Gemini conversation

The Gemini thread ([source](https://gemini.google.com/share/536c3e9635ff)) was a
single-turn Q&A titled "IDE w GitHub Codespaces" about available IDE frontends
in Codespaces. It confirmed that browser VS Code, desktop VS Code, JetBrains
Gateway, and CLI-only modes are all viable.

---

## Open Questions

- [ ] Does the devcontainer build cleanly in Codespaces? (not yet tested)
- [ ] Are all essential tools available after `postCreateCommand` completes?
- [ ] Does the GitHub MCP HTTP endpoint work inside the Codespace?
- [ ] Does the Azure MCP Server extension work without additional Azure auth setup?
- [ ] Should the Dev Container use a custom Dockerfile instead of the features approach?
- [ ] Is Codespace boot time acceptable for regular development?
