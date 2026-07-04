---
source: Copilot Chat (session)
model: DeepSeek V4 Pro
date: 2026-07-04
---

# OpenCode Hosting — Codespaces vs Homelab/Cloudlab

## Topic

A comparison of where and how to run OpenCode as a persistent, agentic
development server — GitHub Codespaces vs running on the Homelab/Cloudlab
hosts, and within those hosts, as a bare host service vs a Docker container.
The evaluation covers server-mode daemon operation, git project access,
multi-project workspace support, sandboxing, dependency installation, session
backup, and background automation.

**Homelab and Cloudlab are treated interchangeably** — Cloudlab is the dev
environment for Homelab (ADR 13), running the same Ansible-managed stack.
Both run Ubuntu 24.04, both have Docker and Caddy. Cloudlab is the deployment
target for the OpenCode sandbox; the Homelab M910q could serve the same role
but is intentionally kept focused on production services. SSH access to both
hosts is required regardless of where OpenCode runs — the agent needs to
execute Ansible playbooks against the M910q and manage the Cloudlab VPS itself.

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

### 2. Homelab / Cloudlab as OpenCode hosts

Both Homelab (M910q) and Cloudlab (Contabo VPS 10) run Ubuntu 24.04 with
Docker and Caddy, managed via Ansible. They differ in role: the M910q runs
production services, Cloudlab is the dev/playground environment. Either could
host OpenCode; Cloudlab is the preferred target to keep the M910q focused.

OpenCode can be deployed in two modes on these hosts:

#### 2a. Host service (bare metal, Ansible-managed)

OpenCode installed directly on the host via an Ansible role, running as a
`systemd` service. Projects are cloned to the host filesystem. Caddy
reverse-proxies the WebUI. The entire setup is declarative and reproducible
via the same Ansible workflow that already manages both hosts.

**Pros:** No Docker overhead. Direct filesystem access to all projects. Simplest
Ansible integration — `ansible-playbook` runs natively on the same host.
Declarative and reproducible via the existing Ansible infrastructure.

**Cons:** No sandbox isolation — OpenCode has access to the host filesystem,
SSH keys, and Docker socket. Dependency conflicts possible between OpenCode's
tooling and host packages. Cleanup means reverting Ansible state, not just
removing a container.

#### 2b. Docker container (sandbox)

OpenCode runs as a container via the official image `ghcr.io/anomalyco/opencode`
(or a custom extension of it with project tooling). Projects are bind-mounted
or cloned inside a Docker volume. Caddy reverse-proxies to the container port.

**Pros:** Sandbox isolation — no host access, no Docker socket. Reproducible —
the image is the single source of truth. Easy teardown (`docker rm`). Matches
the Codespaces model (containerized dev environment). Session data lives in a
named Docker volume, trivially backed up.

**Cons:** Slightly more setup (Dockerfile, compose file, image build). Tooling
must be baked into the image or installed at container start. SSH to M910q and
Cloudlab still works — the sandbox is just another SSH client.

### 3. Windows workstation

The primary daily-driver workstation (Windows 11) could run OpenCode locally
as a desktop application or via WSL. This is how it's used today for
interactive TUI sessions (ADR 17's Codespaces-based workflow).

**Pros:** Zero latency — everything runs on local hardware. No network
dependency for the agent itself (only for LLM API calls). Direct access to
local files, Windows credential store (DPAPI), and VS Code. Fastest
interactive experience.

**Cons:** Not a server — the workstation sleeps, reboots, or goes offline.
No 24/7 availability; background automations only run when the machine is
awake. Not accessible from other machines (laptop, tablet, phone) without
additional remote desktop setup. No sandbox isolation unless running inside
WSL or a VM.

### 3. Sandbox dependency installation strategy

The sandbox needs two categories of tools:

| Category | Provided by |
|---|---|
| OpenCode runtime (server, WebUI, MCP, sessions, API) | Official image `ghcr.io/anomalyco/opencode` |
| Project tooling (Ansible, Az PowerShell, Bicep, Azure CLI, GitHub CLI, Node.js) | Custom Dockerfile extending the official image |

**Approach: custom Dockerfile extending the official image.**

OpenCode publishes an official Docker image at `ghcr.io/anomalyco/opencode`,
and has first-class headless server support via `opencode serve` (API-only) and
`opencode web` (API + built-in browser WebUI). The official image provides the
OpenCode runtime; a thin custom Dockerfile adds the project-specific tooling
the agent needs to invoke via bash:

```dockerfile
FROM ghcr.io/anomalyco/opencode:latest
RUN apt-get update && apt-get install -y ansible ansible-lint curl git jq
RUN curl -fsSL -o /usr/local/bin/bicep \
    https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64 \
    && chmod +x /usr/local/bin/bicep
# PowerShell, Az module, Node.js — heavier layers, candidates for a separate build stage
```

This is cleaner than the earlier `devcontainer.json`-derived approach —
`devcontainer.json` carries VS Code extensions, IDE settings, and user-setup
logic that is irrelevant for a headless server. It remains the source of truth
for Codespaces (interactive dev); the Dockerfile is the source of truth for the
sandbox (headless server).

**For future projects:** adding a tool to the Dockerfile + rebuilding the image
propagates the change. If a project needs a conflicting dependency, that's the
trigger for per-project sandboxes with per-project Dockerfiles.

### 4. Headless automation via `opencode run`

OpenCode's CLI supports non-interactive agent execution against a running server:

```bash
opencode run --attach http://localhost:4096 --agent homelab \
  "Run the weekly DR validation and report results"
```

This enables scheduled background tasks via `systemd` timers on the host that
`docker exec` into the sandbox — something impossible in Codespaces.

### 5. Architecture overview

```
Cloudlab VPS (Contabo, €5.50/mo) — Ansible-managed, Ubuntu 24.04
├── Docker
│   └── opencode-sandbox (ghcr.io/anomalyco/opencode + project tooling)
│       ├── /workspaces/              (bind-mounted or volume, all git repos)
│       ├── opencode-data/            (Docker volume, session persistence)
│       └── opencode web --hostname 0.0.0.0 --port 4096
├── Caddy (reverse proxy)
│   └── opencode.example.com → opencode-sandbox:4096
├── Cloudflare Tunnel (secure remote access)
├── systemd timer → docker exec opencode restic → Azure Blob
├── SSH → M910q (Ansible playbook execution)
└── SSH → self (Cloudlab management via Ansible)

M910q (production)
├── Docker stack (Caddy, DNSMasq, Portainer, Gitea, etc.)
└── No OpenCode overhead — Cloudlab handles it

Windows workstation (primary interactive client)
├── OpenCode Desktop App or VS Code → connects to Cloudlab server
│   └── opencode attach https://opencode.example.com
├── Also runs OpenCode TUI locally for quick interactive sessions
└── Connects from anywhere via Cloudflare Tunnel

Codespaces (interactive fallback only)
└── ADR 14 / ADR 17 — emergency browser-based access
```

### 6. Comparison summary

| Dimension | Codespaces | Homelab / Cloudlab (host service) | Homelab / Cloudlab (Docker container) | Windows workstation |
|---|---|---|---|---|
| Server mode (daemon) | ❌ Idle timeout | ✅ `systemd` service, 24/7 | ✅ Docker container, 24/7 | ❌ Sleeps/reboots; not 24/7 |
| GitHub repos | ✅ Native clone | ✅ `git clone` via `GH_PAT` | ✅ `git clone` via `GH_PAT` | ✅ Native clone |
| Multi-project workspace | ❌ 1:1 repo model | ✅ All repos on host filesystem | ✅ All repos in bind-mounted dir | ✅ Local filesystem |
| Sandbox isolation | ✅ (Codespace IS a container) | ❌ Full host access | ✅ Container isolation | ❌ No isolation (unless WSL/VM) |
| Dependencies | ✅ `devcontainer.json` Features | ✅ Ansible role — declarative | ✅ Baked into Docker image | ⚠️ Manual install or WSL |
| Regular backup | ❌ No cron | ✅ `systemd` timer + `restic` | ✅ `systemd` timer + `restic` (Docker volume) | ⚠️ Manual or local backup only |
| Background automations | ❌ | ✅ `systemd` timer triggers `opencode run` | ✅ `systemd` timer → `docker exec opencode run` | ❌ Only when machine is awake |
| SSH to M910q + Cloudlab | ✅ Via KV-stored key | ✅ Native SSH | ✅ SSH from inside container (same key) | ✅ Native SSH |
| Reproducibility | ✅ Full rebuild from `devcontainer.json` | ✅ Ansible role — declarative, idempotent | ✅ Image is single source of truth | ❌ Ad-hoc install, state drifts |
| Cleanup | ✅ Delete Codespace | ✅ Revert Ansible state | ✅ `docker rm` + delete volume | ❌ Manual uninstall |
| Cost (24/7) | ~€60/mo (paid tier) | ~€0 M910q / €5.50/mo Cloudlab | ~€0 M910q / €5.50/mo Cloudlab | ~€0 (hardware already owned) |
| Separation from production | ✅ | ❌ M910q: same host as prod services | ✅ M910q: container isolated from host | ✅ Separate machine |
| Remote access from other machines | ✅ Browser-based (any device) | ✅ WebUI via Caddy + Cloudflare Tunnel | ✅ WebUI via Caddy + Cloudflare Tunnel | ❌ Workstation only (or RDP/VNC overhead) |

---

## Decision Path

1. **Started:** OpenCode in Codespaces (ADR 17) — working, but TUI-only.
2. **Added server mode** → Codespaces eliminated (idle timeout, no cron).
3. **Compared host service vs Docker container** → Docker container selected for
   sandbox isolation and clean teardown. Both are Ansible-managed, so
   reproducibility is a wash; the differentiator is that host service grants
   OpenCode full access to the host (filesystem, SSH keys, Docker socket),
   which violates the sandbox requirement.
4. **Considered Windows workstation** → good for interactive TUI sessions (zero
   latency, local files) but fails on server mode and remote access. Not a
   24/7 host; can't be reached from other machines without RDP/VPN overhead.
   Best role: primary interactive client that attaches to the Cloudlab server.
5. **Selected Cloudlab as deployment target** — already provisioned, already
   Ansible-managed, €5.50/mo already paid. M910q kept focused on production
   services but could serve the same role if needed.
6. **Selected official image + custom Dockerfile** over devcontainer.json-derived
   image — cleaner separation: OpenCode runtime from `ghcr.io/anomalyco/opencode`,
   project tooling from a thin custom layer.

---

## Open Questions

- **Official image internals:** What base does `ghcr.io/anomalyco/opencode` use?
  Does it have `apt` for adding project tooling, or is it a distroless/scratch
  image that requires a multi-stage build?
- **OpenCode server mode MCP behavior:** Does `opencode serve`/`opencode web`
  handle MCP tool invocations the same way as TUI mode? Specifically, local
  stdio MCP servers (Azure MCP via `npx`) — do they spawn inside the container
  and use the container's env vars?
- **OpenCode Desktop App connectivity:** Does the Desktop App connect to a
  remote OpenCode server (`opencode attach`), or only to a local one? If
  remote is supported, does it work through Caddy + Cloudflare Tunnel?
- **Per-project sandbox graduation trigger:** At what point does a single shared
  sandbox become insufficient — conflicting tool versions, resource isolation,
  or security boundaries between projects?
- **Headless automation:** Confirmed via `opencode run --attach`. Need to test
  whether it works with `--agent` flag to select a specific agent, and whether
  the exit code reflects success/failure (needed for `systemd` service health).

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
