# Run OpenCode as a Docker Sandbox (Homelab / Cloudlab)

**Date:** 2026-07-04
**Status:** Proposed

---

## Context

ADR 17 adopted OpenCode as the primary agentic development tool, initially
deployed in GitHub Codespaces. That decision explicitly scoped out two areas:

- **Background automations / scheduled agent tasks** — not investigated
- **Cross-machine session sharing** — local to one Codespace

Subsequent evaluation ([research 20](../research/20-opencode-hosting-codespaces-vs-homelab.md))
identified that Codespaces cannot serve as a persistent OpenCode server:
idle timeout (~30 min), no cron, and 1:1 repo model block server-mode daemon
operation, multi-project workspaces, scheduled automations, and cross-project
backup.

New requirements emerged that reshape the hosting decision:

| Priority | Requirement |
|---|---|
| Must | Persistent server daemon — `opencode web` with HTTP API + WebUI, connectable from OpenCode Desktop App and browser |
| Must | Sandbox isolation — agent runs in a Docker container, no host access |
| Must | Regular automated backup of all session data across projects |
| Must | Project tooling (Ansible, Az PowerShell, Bicep, etc.) available in the sandbox |
| Nice-to-have | All projects accessible as one workspace in one OpenCode instance |
| Nice-to-have | Per-project sandbox isolation |

OpenCode publishes an official Docker image (`ghcr.io/anomalyco/opencode`) with
first-class headless server support (`opencode serve` for API-only, `opencode web`
for API + built-in browser WebUI) and non-interactive agent execution
(`opencode run --attach`).

Both the Homelab M910q (ADR 01) and the Contabo Cloudlab VPS (ADR 13) run
Ubuntu 24.04 with Docker and Caddy, managed via Ansible. They are treated
interchangeably for this decision — the same Ansible role deploys the same
Docker container to either host.

---

## Decision

**Run OpenCode as a Docker container** on the Homelab/Cloudlab hosts, extending
the official `ghcr.io/anomalyco/opencode` image with project-specific tooling.
The setup is Ansible-managed and identical across both hosts — an Ansible role
(`opencode_sandbox/`) builds the custom image and deploys the container. This
ADR extends ADR 17 — OpenCode remains the tool, but the hosting model shifts
from Codespaces (interactive TUI) to Homelab/Cloudlab (persistent Docker sandbox).

Key design choices:

1. **Official image as base** — `ghcr.io/anomalyco/opencode` provides the
   OpenCode runtime (server, WebUI, MCP, sessions, API). A thin custom
   Dockerfile adds project tooling (Ansible, Az PowerShell, Bicep, Azure CLI,
   GitHub CLI, Node.js). Cleaner than the earlier `devcontainer.json`-derived
   approach — `devcontainer.json` carries VS Code extensions and IDE settings
   irrelevant for a headless server.
2. **Sandbox isolation** — no host mounts beyond the workspace directory, no
   `--privileged`, no Docker socket. The agent can't touch the host filesystem
   or SSH keys except what's explicitly provided.
3. **Session persistence** — Docker named volume for OpenCode's data directory.
   Survives container rebuilds. Backed up nightly via `systemd` timer →
   `restic` to Azure Blob (reusing ADR 02's backup infrastructure).
4. **WebUI access** — Caddy reverse-proxies `opencode.example.com` (or
   `opencode.home` on LAN) to the container's `opencode web` port. Cloudflare
   Tunnel (ADR 08) provides secure remote access from the Windows workstation
   or any browser.
5. **SSH to managed hosts** — the sandbox container has SSH configured for
   both M910q and Cloudlab, using the same KV-stored key as Codespaces today.
   OpenCode's agent can execute Ansible playbooks against both hosts.
6. **Background automations** — `systemd` timers on the host trigger
   `docker exec opencode opencode run --attach` for scheduled agent tasks.
   Something impossible in Codespaces.
7. **Windows workstation** — remains the primary interactive client. The
   OpenCode Desktop App or VS Code connects to the server via
   `opencode attach`. Local TUI sessions still work for quick edits.

Out of scope for this decision:

- **Cross-machine session sharing** — same as ADR 17. Sessions live on one
  host; no SQLite-over-network architecture.
- **Per-project sandbox graduation** — single sandbox for now. Graduation
  trigger is documented in research 20 as an open question.
- **Which specific host to deploy to** — the Ansible role targets both.
  Cloudlab is the natural first target (dev environment, no production
  services to disturb), but the setup is identical on the M910q.

---

## Consequences

### Positive

- **Persistent 24/7 server.** No idle timeout. OpenCode WebUI reachable from
  any device via Cloudflare Tunnel. The agent is always available.
- **Sandbox isolation.** Container has no access to the host filesystem, SSH
  keys, or Docker socket. Clean teardown: `docker rm` + delete volume.
- **Reproducible environment.** The custom Dockerfile + Ansible role are the
  single source of truth for the sandbox. Deployable to any Ubuntu 24.04 host
  with Docker. `devcontainer.json` remains the source of truth for Codespaces
  (interactive dev).
- **Automated backup.** Nightly `systemd` timer → `restic` to Azure Blob covers
  all session data across all projects. No manual `Backup-OpencodeData.ps1`.
  Retention policies via restic's `forget` policy.
- **Background automations.** `systemd` timers trigger headless agent runs via
  `opencode run --attach`. Enables scheduled DR validation, health checks,
  cost reports — use cases ADR 17 explicitly left open.
- **Multi-project workspace.** One OpenCode instance serves all git repos
  cloned into the sandbox. One WebUI, one backup target, one config.
- **Ansible-native.** The same Ansible infrastructure that manages the hosts
  also manages the sandbox. No new tooling or workflow.
- **Remote access from any machine.** Browser-based WebUI via Cloudflare Tunnel
  means the primary workstation, a laptop, a tablet, or a borrowed machine can
  all reach OpenCode. Not tied to one desktop.

### Negative

- **Docker image maintenance.** The custom Dockerfile must be kept in sync with
  project tooling needs. Each new dependency requires an image rebuild.
- **Single point of failure per host.** If the host goes down, OpenCode is
  unavailable on that host. Mitigation: deploy to both Homelab and Cloudlab;
  Codespaces remains as interactive fallback (ADR 14).
- **No SSO/auth on WebUI.** `opencode web` supports HTTP basic auth only
  (`OPENCODE_SERVER_PASSWORD`). Cloudflare Tunnel adds a layer, but there's no
  Entra ID or GitHub OAuth integration. Acceptable for a single-user homelab.

### Alternatives Considered

- **Codespaces as server host** — rejected per research 20. Idle timeout, no
  cron, 1:1 repo model. Cannot meet server mode or background automation
  requirements.
- **Host service (bare metal, no Docker)** — rejected. Ansible-managed host
  service is reproducible, but grants OpenCode full host access (filesystem,
  SSH keys, Docker socket), violating the sandbox requirement.
- **Windows workstation as server** — rejected. Not a 24/7 host; sleeps/reboots;
  not reachable from other machines without RDP overhead. Best role: primary
  interactive client.
- **`devcontainer.json`-derived image** — rejected in favor of the official
  `ghcr.io/anomalyco/opencode` image. `devcontainer.json` carries VS Code
  extensions, IDE settings, and user-setup logic irrelevant for a headless
  server. Cleaner to start from the official OpenCode image and add only
  what the agent needs.

---

> **References:**
> - [ADR 17 — Adopt OpenCode](260628-17-adopt-opencode.md)
> - [ADR 13 — VPS Playground (Cloudlab)](260616-13-vps-playground.md)
> - [ADR 08 — Cloudflare Tunnel](260530-08-remote-access-cloudflare-tunnel.md)
> - [ADR 07 — Caddy Reverse Proxy](260529-07-reverse-proxy-caddy.md)
> - [ADR 02 — Backup Strategy](260524-02-backup-strategy-restic-blob.md)
> - [ADR 01 — Hardware Selection (M910q)](260520-01-hardware-selection-m910q.md)
> - [Research 20 — OpenCode Hosting Comparison](../research/20-opencode-hosting-codespaces-vs-homelab.md)
