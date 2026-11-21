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

`mcr.microsoft.com/devcontainers/base:ubuntu26.04` — Ubuntu 26.04 LTS (Python 3.14,
supported to 2031). The lab hosts stay on 24.04; the container only needs SSH access
to them, not a matching OS.

### Features (via devcontainers/features)

| Feature | Purpose |
|---|---|
| `docker-outside-of-docker` | Docker CLI + Compose (bind-mounts host socket) |
| `powershell` | PowerShell 7 — default terminal profile |
| `azure-cli` | Azure CLI for ad-hoc queries |
| `github-cli` | GitHub CLI for PR/issue management |
| `node` | Node LTS — npx-driven MCP servers (Azure MCP) |
| `kubectl-helm-minikube` | kubectl v1.37.2 + helm v4.3.2 (pinned per ADR 52) for the k3s / Azure Arc cluster (ADR 22); minikube disabled |
| `python` | Python + pip — Ansible controller env (collections with Python deps) |
| `git-lfs` | Git LFS — PDFs are stored in LFS (`.gitattributes`) |

### VS Code extensions

Bicep, PowerShell, Ansible, Mermaid, Docker, GitHub PR, DeepSeek V4 for Copilot Chat,
Azure MCP Server, Mistral Vibe (`mistralai.mistral-vibe-code`). Copilot and Copilot
Chat are built into current VS Code and are deliberately not listed (listing them
errors with "cannot be downgraded" on rebuild).

### Post-create scripts (`.devcontainer/scripts/`)

| Script | What it installs | Idempotent? |
|---|---|---|
| `setup-ansible.sh` | `ansible-core==2.22.*` + `ansible-lint==26.*` via a pinned pip venv in `/opt` (apt caps ansible-core per Ubuntu release) | ✅ skips if the pinned versions are already installed |
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

## SSH to the VPS from the DevContainer

The dev container starts `ssh-agent` but loads **no** SSH identity: an `ssh` call or an Ansible run
fails until you load one deliberately. `cloudlab` (the Contabo VPS) is not certificate-enabled, so it
keeps its own key:

```powershell
./scripts/Import-HomelabCloudlabKey.ps1
```

Everything else on the fleet takes a step-ca certificate instead — `automation` for operator
automation, `agent-ai` for an AI agent, and the fleet key only for break-glass. The
[`fleet-connect` skill](../../.github/skills/fleet-connect/SKILL.md) lists the loaders; each one runs
`Reset-HomelabSshIdentity.ps1` first, so a new identity replaces the previous one instead of
stacking on top of it.

### Create SSH config (one-time setup)

Run this **once** (not per-session):

```powershell
@"
Host cloudlab
    HostName 173.249.27.13
    User fleetadm
"@ | Set-Content ~/.ssh/config
```

Connect:

```powershell
ssh cloudlab
```

---

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
| Rebuild fails instantly with `Docker returned an error code 1` / `failed to connect … npipe:////./pipe/docker_engine` | Docker daemon not running (Rancher Desktop / Docker Desktop stopped) — this is what "crashed" the container on 2026-11-21 | Start the daemon (`rdctl start` for Rancher Desktop), confirm `docker version` shows a Server section, then rebuild |
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

### OpenCode out, Mistral Vibe in — and Vibe sessions ARE persisted

OpenCode is no longer installed or persisted inside the Dev Container — the
`sst-dev.opencode` extension, the `setup-opencode*.ps1/.sh` post-create steps,
and the `/workspaces/.opencode` symlink wiring were removed. Use the **Mistral Vibe**
extension (`mistralai.mistral-vibe-code`, preinstalled) instead; it bundles the agent.

Vibe keeps its config, logs and **sessions** under `~/.vibe`. The container mounts a
named Docker volume there (`vibe-home-${localWorkspaceFolderBasename}` → `/home/vscode/.vibe`,
i.e. `vibe-home-Homelab` for this checkout — see `devcontainer.json` `mounts`), so Vibe
sessions survive `Dev Containers: Rebuild Container`. The volume name is scoped per
checkout on purpose: Vibe stores provider credentials in `~/.vibe`, and a fixed name
would share them with every other project on the same Docker host. The project-local
`.vibe/` directory lives in the workspace mount and is persistent too. Inspect the volume
with `docker volume inspect vibe-home-Homelab`.

Two gotchas that otherwise surface as `EACCES ... /home/vscode/.vibe/logs` from the
Vibe extension: a named-volume mountpoint is **root-owned** by default, so
`postCreateCommand` starts with `sudo chown -R vscode:vscode /home/vscode/.vibe`;
and `containerEnv` pins `VIBE_HOME=/home/vscode/.vibe` — the extension and CLI read
`$VIBE_HOME` (default `~/.vibe`) to locate config, `logs/` and sessions.

Only in-container sessions (extension + CLI) live on this volume. **Vibe Code web**
sessions (https://chat.mistral.ai/code) run in Mistral's hosted cloud sandbox and are
managed there, not in the container — ADR 53 lists all Vibe surfaces.

[Runbook 15](15-opencode-session-persistence.md) is superseded for the Dev Container; its
backup / web-server sections document the historical Codespaces deployment only. Cloudlab
OpenCode instances (runbooks 17/18) keep their data under `/var/lib/opencode/instances/<name>/`
and their backup is a follow-up there (runbook 17) — runbook 15 does not apply to them.

| Persistence layer | What survives | Where it lives |
|---|---|---|
| Container filesystem | Nothing — wiped on rebuild | (none) |
| `vibe-home-Homelab` volume (per-checkout name) | `~/.vibe` — Vibe config, logs, sessions | `/home/vscode/.vibe` |
| `/workspaces` (bind mount / Codespaces disk) | Everything under it | Repo clone + project-local `.vibe/` |

## Dev Container Architecture

```
.devcontainer/
├── devcontainer.json          # Main config — image, features, extensions, scripts
└── scripts/
    ├── setup-ansible.sh       # pinned pip venv: ansible-core 2.22 + ansible-lint 26 (idempotent)
    ├── setup-bicep.sh         # Bicep CLI binary (idempotent)
    └── setup-azps.ps1         # Az PowerShell module (idempotent, backgrounded)
```
