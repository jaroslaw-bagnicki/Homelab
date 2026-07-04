---
source: Copilot Chat (session)
model: DeepSeek V4 Pro
date: 2026-07-04
---

# OpenCode Hosting — Codespaces vs Homelab vs Cloudlab

## Topic

A comparison of where to run OpenCode as a persistent, agentic development server
for the Homelab project — GitHub Codespaces, the physical M910q server, or the
Contabo Cloudlab VPS. The evaluation covers server-mode daemon operation, git
project access, multi-project workspace support, sandboxing, dependency
installation, session backup, and background automation.

The conversation started from the existing decision to adopt OpenCode in
Codespaces (ADR 17) and progressively added constraints that reshaped the
landscape: server mode (not TUI), multi-project workspace, sandbox isolation,
and per-project sandbox isolation.

---

## Requirements (final constraint set)

| Priority | Requirement |
|---|---|
| Must | Run as a persistent server daemon (HTTP API + WebUI), not ephemeral TUI — connectable from OpenCode Desktop App and browser |
| Must | Work with git projects hosted on GitHub |
| Must | Regular backup of all session data across all projects |
| Must | Sandboxed — OpenCode agent runs in a container with no host access |
| Must | Dependencies (Ansible, Az PowerShell, Bicep, etc.) installed in the sandbox |
| Nice-to-have | All projects accessible as one workspace in a single OpenCode instance |
| Nice-to-have | Per-project sandbox isolation |

---

## Key Findings

### 1. GitHub Codespaces — ruled out by server mode requirement

Codespaces are designed for interactive, start-stop development sessions. A
persistent daemon conflicts with the platform's core design:

- **Idle timeout** — Codespaces auto-suspend after ~30 min of inactivity. A
  background daemon doesn't count as "activity." Keepalive hacks are brittle
  and against platform intent.
- **Cost at 24/7 scale** — 60 core-hours/month free tier covers occasional use;
  a persistent server would burn ~730 core-hr/mo at ~€60/mo standard rates.
- **Multi-project workspace** — Codespaces are 1:1 with repos. Multiple repos
  can be cloned into one Codespace but don't survive rebuilds without custom
  scripting.
- **Cross-project backup** — Impossible without external orchestration. No cron
  inside a Codespace; GitHub Actions can't reach the filesystem of a running
  Codespace.

**Codespaces remain valid as interactive fallback** (ADR 14's original purpose)
but cannot serve as the OpenCode server host.

### 2. Homelab M910q — ruled out by sandbox + hardware constraints

The M910q (i5-7500T, 4C/4T, 16 GB RAM, 256 GB NVMe) is already running the
production Docker stack (Caddy, DNSMasq, Portainer, Gitea, etc.). Adding
OpenCode sandbox containers would exceed its capacity:

- **CPU contention** — 4C/4T without Hyper-Threading (ADR 01). Production
  Docker stack + one or more sandbox containers would push against the ceiling.
- **RAM pressure** — 16 GB shared between production services and sandboxes.
- **Storage** — 256 GB NVMe is already tight (ADR 01). Sandbox images + git
  clones + session DBs compound this.

The M910q remains focused on production services.

### 3. Contabo Cloudlab VPS — selected for OpenCode server

The existing Contabo Cloud VPS 10 (4 vCPU, 8 GB RAM, 75 GB NVMe, €5.50/mo,
ADR 13) is already provisioned, Ansible-managed, and serves as the Ansible
playground. Repurposing part of its capacity for OpenCode sandboxes adds no
cost.

| Factor | Assessment |
|---|---|
| Server mode | ✅ 24/7 host. OpenCode runs as a `systemd`-managed Docker container behind Caddy. |
| GitHub repos | ✅ Cloned inside sandbox container via `GH_PAT`. |
| Multi-project | ✅ All repos cloned into one sandbox; one OpenCode instance serves all. |
| Sandbox | ✅ Docker container — no host mounts, no `--privileged`, no Docker socket. |
| Dependencies | ✅ Installed via custom Docker image built from `devcontainer.json` spec (single source of truth). Ansible role automates build and deploy. |
| Backup | ✅ `systemd` timer tars the Docker volume → `restic` to Azure Blob (ADR 02). |
| Ansible access | ✅ SSH from sandbox to M910q via KV-stored key (same as Codespaces today). |
| Cost | ✅ €5.50/mo already paid — no incremental cost. |
| Resilience | ✅ Separate host from production M910q — one failing doesn't take down the other. |

### 4. Sandbox dependency installation strategy

The sandbox needs the same tooling as the Codespace: Ansible, Az PowerShell,
Bicep, Azure CLI, GitHub CLI, Node.js, PowerShell, Docker CLI, OpenCode.

**Selected approach: Ansible role builds a Docker image from the existing
`devcontainer.json` spec.**

The `.devcontainer/devcontainer.json` already defines all tooling via Dev
Container Features + post-create scripts. Instead of duplicating this in a
standalone Dockerfile, an Ansible role (`opencode_sandbox/`) uses the
`devcontainer` CLI to build an image directly from the spec:

```
devcontainer build --workspace-folder . --image-name opencode-sandbox:latest
```

This eliminates duplication — `devcontainer.json` remains the single source of
truth for all tooling. The same image works for Codespaces (interactive) and
the Cloudlab sandbox (headless server).

**For future projects:** adding a tool to `devcontainer.json` + rebuilding the
image propagates the change to all projects in the shared sandbox. If a project
needs a conflicting tool (e.g., different Python version), that's the trigger
to graduate to per-project sandboxes via per-project Dockerfiles that extend
the base image.

### 5. Architecture overview

```
Cloudlab VPS (Contabo, €5.50/mo)
├── docker compose
│   └── opencode-sandbox (single container, all projects)
│       ├── /workspaces/homelab       (volume mount)
│       ├── /workspaces/project-b     (volume mount, future)
│       └── /home/vscode/.opencode    (Docker volume, session persistence)
├── Caddy (reverse proxy)
│   └── opencode.example.com → opencode-sandbox:3000
├── Cloudflare Tunnel (secure remote access)
├── systemd timer → restic backup → Azure Blob (homelabcloud5/opencode-backups/)
└── SSH → M910q (Ansible playbook execution)

M910q (production)
├── Docker stack (Caddy, DNSMasq, Portainer, Gitea, etc.)
└── No OpenCode overhead
```

### 6. Comparison summary

| Dimension | Codespaces | M910q | Cloudlab |
|---|---|---|---|
| Server mode (daemon) | ❌ Idle timeout | ✅ | ✅ |
| GitHub repos | ✅ | ✅ | ✅ |
| Multi-project workspace | ❌ 1:1 repo model | ⚠️ HW constrained | ✅ |
| Sandbox isolation | ✅ (already a container) | ⚠️ HW constrained | ✅ |
| Dependencies from devcontainer.json | ✅ Native | ⚠️ Extra setup | ✅ Ansible role |
| Regular backup | ❌ No cron | ✅ systemd timer | ✅ systemd timer |
| Background automations | ❌ | ✅ | ✅ |
| Ansible access | ⚠️ SSH hop | ✅ Local | ⚠️ SSH to M910q |
| Hardware headroom | 4 vCPU / 16 GB dedicated | 4C/4T / 16 GB shared | 4 vCPU / 8 GB dedicated |
| Cost (24/7) | ~€60/mo (paid tier) | ~€0 incremental | €5.50/mo (already paid) |
| Separation from production | ✅ | ❌ Same host | ✅ Separate host |

---

## Decision Path

1. **Started:** OpenCode in Codespaces (ADR 17) — working, but TUI-only.
2. **Added server mode** → Codespaces eliminated (idle timeout).
3. **Added sandbox** → M910q eliminated (hardware contention).
4. **Selected:** Cloudlab VPS — already provisioned, already Ansible-managed,
   €5.50/mo already paid, sufficient headroom for one shared sandbox container.

---

## Open Questions

- **OpenCode server mode MCP behavior:** Does OpenCode in server mode handle
  MCP tool invocations the same way as TUI mode? Specifically, local stdio MCP
  servers (Azure MCP via `npx`) — do they spawn inside the sandbox container
  and use the container's env vars?
- **OpenCode Desktop App connectivity:** Does the Desktop App connect to a
  remote OpenCode server, or only to a local one? If remote is supported, what
  authentication mechanism?
- **Per-project sandbox graduation trigger:** At what point does a single shared
  sandbox become insufficient — conflicting tool versions, resource isolation,
  or security boundaries between projects?
- **Background automation in sandbox:** Can OpenCode server mode trigger
  headless agent tasks (scheduled via systemd timer on the host that
  `docker exec`s into the sandbox)? Does OpenCode support a CLI invocation
  mode for scripted agent runs?

---

## References

- [ADR 01 — Hardware Selection (M910q)](../decisions/260520-01-hardware-selection-m910q.md)
- [ADR 02 — Backup Strategy (restic + Blob)](../decisions/260524-02-backup-strategy-restic-blob.md)
- [ADR 03 — Container Strategy (Docker Compose)](../decisions/260524-03-container-strategy.md)
- [ADR 04 — Hybrid Cloud (Arc)](../decisions/260524-04-hybrid-cloud-azure-arc.md)
- [ADR 07 — Reverse Proxy (Caddy)](../decisions/260529-07-reverse-proxy-caddy.md)
- [ADR 13 — VPS Playground (Cloudlab)](../decisions/260616-13-vps-playground.md)
- [ADR 14 — Codespaces Adoption](../decisions/260618-14-codespaces-adoption.md)
- [ADR 15 — Copilot Desktop Evaluation (Deferred)](../decisions/260625-15-copilot-desktop-agentic.md)
- [ADR 16 — Codespaces SP](../decisions/260628-16-gh-codespaces-sp-for-homelab.md)
- [ADR 17 — OpenCode Adoption](../decisions/260628-17-adopt-opencode.md)
- [Research 16 — Codespaces & Dev Containers](16-github-codespaces-devcontainers.md)
- [Research 19 — Copilot Desktop Agentic](19-copilot-desktop-agentic.md)
