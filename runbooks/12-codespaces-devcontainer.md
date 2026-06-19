# GitHub Codespaces & Dev Container Setup

> How to use the Homelab dev container for browser-based development — no local
> install needed.

## Overview

The repository includes a `.devcontainer/devcontainer.json` that defines a
consistent development environment. Opening the repo in a GitHub Codespace
automatically provisions a cloud VM with all tools pre-configured.

This is especially useful when working from a **corporate/locked-down machine**
where cloning the repo or installing tooling isn't practical — just open the
repo in a Codespace and use VS Code in the browser.

## Quick Start

### Create or resume your Codespace

1. Go to [github.com/codespaces](https://github.com/codespaces)
   - **First time**: Click **Create codespace on jaroslaw-bagnicki/Homelab**
   - **Returning**: Click the existing `Homelab` codespace to resume (usually instant)
2. Wait for the environment to initialize (~2–3 min on first build, seconds if resuming)
3. You're now in browser VS Code with the full dev container environment

### You're ready to go

VS Code runs in the browser with all tools pre-loaded. Open terminals (Ctrl+``), 
edit files, and commit to the repo — everything is authenticated and ready. 
See [Verifying the Setup](#verifying-the-setup) to confirm tools are available.

## Opening an Existing Codespace via CLI

If the codespace already exists (created from the GitHub web UI or a previous
session), open it directly from the terminal using the GitHub CLI (`gh`).

### List available Codespaces

```bash
gh codespace list
```

Shows all your codespaces with their name, repository, branch, and state
(`Available` — ready to open, `Shutdown` — needs a moment to resume).

### Open a Codespace in VS Code

Opens the codespace in your **local VS Code desktop** app:

```bash
gh codespace code
```

If you have multiple codespaces, you'll be prompted to pick one. You can also
specify by name:

```bash
gh codespace code --codespace $CODESPACE_NAME
```

### Shut down a Codespace

Stops the codespace to preserve disk and core hours:

```bash
gh codespace stop
```

If you have multiple codespaces, you'll be prompted to pick one. To stop a
specific one:

```bash
gh codespace stop --codespace $CODESPACE_NAME
```

> [!TIP]
> To skip the interactive prompt when you have multiple codespaces, pass
> `--codespace` with the name from `gh codespace list`, or use `-c` shorthand.

## What's Included

### Base image

`mcr.microsoft.com/devcontainers/base:ubuntu-24.04` — the same OS version
running on the homelab server.

### Features (via devcontainers/features)

| Feature | Purpose |
|---|---|
| `docker-outside-of-docker` | Docker CLI + Compose (bind-mounts host socket) |
| `powershell` | PowerShell 7 — default terminal profile |
| `azure-cli` | Azure CLI for ad-hoc queries |
| `github-cli` | GitHub CLI for PR/issue management |

### VS Code extensions

Bicep, PowerShell, Ansible, Mermaid, Docker, GitHub PR, Copilot, Copilot Chat,
DeepSeek V4 for Copilot Chat, Azure MCP Server.

### Post-create scripts (`.devcontainer/scripts/`)

| Script | What it installs | Idempotent? |
|---|---|---|
| `setup-ansible.sh` | Ansible via `apt` | ✅ skips if `ansible-playbook` exists |
| `setup-bicep.sh` | Bicep CLI standalone binary | ✅ skips if `bicep --version` works |
| `setup-azps.ps1` | Az PowerShell module | ✅ skips if already listed by `Get-Module` |

> [!NOTE]
> The Az PowerShell script runs in the **background** because the module is
> large and takes several minutes. Check progress with:
> ```bash
> tail -f /tmp/install-az.log
> ```

## Verifying the Setup

Run these checks in the Codespace terminal:

```bash
ansible --version        # Ansible
bicep --version          # Bicep CLI
docker --version         # Docker CLI
git --version            # Git
pwsh -c '$PSVersionTable.PSVersion'  # PowerShell 7
pwsh -c 'Get-Module -ListAvailable Az'  # Az PowerShell
az version              # Azure CLI
```

## Corporate Machine Tips

- **No install needed** — everything runs in the browser at
  `github.com/codespaces`
- **Persist your Codespace** — stop instead of deleting; it'll be
  faster to resume next time
- **Settings sync** — VS Code settings/extensions sync via GitHub
  account, so your theme and keybindings carry over
- **Git credentials** — authenticated automatically via GitHub; `git push`
  works out of the box

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Codespace won't build | `postCreateCommand` timeout | Rebuild container from the command palette: `Dev Containers: Rebuild Container` |
| Az cmdlets unavailable | Background install not finished | Check `tail -f /tmp/install-az.log` |
| `bicep` command not found | Script not run yet | Run `bash .devcontainer/scripts/setup-bicep.sh` manually |
| Docker permission denied | Docker socket not mounted | Ensure `docker-outside-of-docker` feature is enabled |
| Copilot Chat threads disappeared after rebuild | Container filesystem is ephemeral | Session history is stored on the container overlay filesystem, which is wiped on rebuild. Threads cannot be recovered. To preserve threads across rebuilds, see the [Session persistence](#session-persistence) section below. |

## Session Persistence

> [!IMPORTANT]
> **Copilot Chat threads are NOT persisted** between dev container rebuilds. All
> chat history is stored in the container's ephemeral filesystem at
> `~/.vscode-remote/data/User/globalStorage/github.copilot-chat/` and is lost
> when you rebuild the container.

### Workarounds

- **GitHub Copilot Cloud Sync** (recommended) — Recent versions of GitHub Copilot Chat
  (late 2025+) support cloud-synced conversation history when signed in. Threads
  may automatically restore after a rebuild. Check VS Code settings:
  `GitHub Copilot: Configure` → `github.copilot-chat.experimental.historySync`.

- **Backup to persistent storage** — Before rebuilding, manually export important
  threads from the chat history or take screenshots. The `/workspaces/.codespaces/shared/`
  directory survives container rebuilds — you could set up devcontainer lifecycle
  hooks to back up and restore the session store automatically.

- **Use Settings Sync** — Persist your VS Code settings, extensions, and keybindings
  via Settings Sync (gear icon → Settings Sync is On). This preserves your
  environment but not the chat history itself.

## Dev Container Architecture

```
.devcontainer/
├── devcontainer.json          # Main config — image, features, extensions, scripts
└── scripts/
    ├── setup-ansible.sh       # Ansible via apt (idempotent)
    ├── setup-bicep.sh         # Bicep CLI binary (idempotent)
    └── setup-azps.ps1         # Az PowerShell module (idempotent, backgrounded)
```
