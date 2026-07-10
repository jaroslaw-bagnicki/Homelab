---
date: 2026-07-08
sources:
  - https://gemini.google.com/share/215b0e334b18
  - https://gemini.google.com/share/9ab700c799ef
  - https://gemini.google.com/share/68b9117edd0e
  - https://gemini.google.com/share/a4fcdc245489
  - https://gemini.google.com/share/6b9bfa24d3a2
supplements: docs/decisions/17-adopt-opencode.md
---

# OpenCode Sandboxed Architecture on Homelab

## Topic

This research extends ADR 17 (OpenCode adoption) from the current
GitHub-Codespaces-only deployment to a self-hosted, sandboxed, multi-project
OpenCode server running on the Homelab/Cloudlab stack. The five Gemini threads
from 2026-07-08 explore:

- whether to run one shared or multiple per-project OpenCode instances,
- how Docker AI Sandboxes (`sbx`) provide process isolation for agentic coding,
- whether `devcontainer.json` is the right foundation for per-project agent
  environments,
- how OpenCode behaves inside Docker Sandboxes (repository access, worktrees,
  long-lived containers, server mode),
- how to route dynamic OpenCode instances through Caddy behind the existing
  Cloudflare Tunnel wildcard.

The conclusion is a concrete target architecture: **per-project OpenCode
sandboxes on Cloudlab, isolated in a dedicated Docker network, exposed through
a dedicated Caddy ingress instance, with `*-oc.example.com` wildcard routing
via Cloudflare Tunnel.**

---

## Context and constraints

| # | Constraint | Why it matters |
|---|------------|----------------|
| 1 | OpenCode must run **server-side** (`opencode serve`/`opencode web`), not only as an ephemeral TUI | Enables Desktop app and browser access from any device |
| 2 | The agent must be **sandboxed** — no direct host filesystem, Docker socket, or SSH-key access | Prevents a compromised or misguided agent from damaging production services |
| 3 | At least two projects with radically different toolchains must be supported: **Homelab** (Ansible, Bicep, Docker, Linux) and **Prospera** (.NET, SQL, Azure) | Tooling, secrets, and stability requirements differ |
| 4 | Existing ingress is **Cloudflare Tunnel + Caddy** with a `*.example.com` wildcard certificate (ADR 08, ADR 20) | New instances should reuse the wildcard, not require per-hostname DNS edits |
| 5 | Infrastructure is **Ansible-managed** Ubuntu 24.04 on Cloudlab (ADR 13) | New components must fit the existing role-based automation |
| 6 | Sessions and repositories must survive container restarts and be backup-able | Aligns with ADR 02 (Restic) and ADR 17 (persistence) |

---

## Key findings

### 1. One shared OpenCode instance is the wrong default for Homelab + Prospera

The threads started with a business-analysis framing and quickly converged on
a system-architecture conclusion: **run separate OpenCode instances per
project**.

| Dimension | Homelab instance | Prospera instance |
|-----------|------------------|-------------------|
| Business purpose | R&D, open-source showcase, infrastructure experiments | Personal finance / commercial project, high-value data |
| Data criticality | Low–medium (configs, logs, scripts) | High (financial data, forecasts, integrations) |
| Stability requirement | Low — breakage is expected during experiments | High — must be reliable for financial decisions |
| Tooling | Ansible, `ansible-lint`, Docker CLI, kubectl, Bicep | .NET SDK, database migration tools, Azure CLI |
| Secrets profile | Azure SP for infra, SSH to hosts | Financial APIs, database connection strings |
| Update cadence | Aggressive — test new plugins, versions, network configs | Conservative — only validated changes |

**Risks of a single shared instance:**

- **Shared database of issues, sessions, and CI/CD variables** — a Homelab
  experiment can corrupt or leak Prospera context.
- **Blast radius** — a bad plugin or config change in the Homelab sandbox
  paralyses Prospera work.
- **Secret commingling** — financial secrets and infrastructure secrets live
  in the same SQLite DB and environment.
- **Different RTO/RPO** — Prospera needs light, frequent backups; Homelab
  generates large, noisy artifacts that would bloat Prospera snapshots.

**Decision reached:** deploy at least two logical instances:
`opencode-homelab` and `opencode-prospera`. Each has its own Docker Compose
file, named volumes, and subdomain.

---

### 2. Docker AI Sandboxes (`sbx`) are the preferred isolation primitive

Docker Sandboxes run each agent session inside a **microVM** with its own
kernel, dedicated Docker daemon, isolated network stack, and root filesystem.
This is stronger isolation than a standard container (shared kernel) and is
explicitly designed for autonomous coding agents.

**Relevant `sbx` facts:**

| Fact | Detail |
|------|--------|
| CLI | `sbx run opencode <path>` or `sbx run opencode --clone <repo>` |
| Base image for OpenCode | `docker/sandbox-templates:opencode` (official template) |
| Isolation | microVM via KVM; each sandbox gets its own kernel and Docker daemon |
| Networking | Default deny for raw TCP/UDP/ICMP; only HTTP/HTTPS egress allowed |
| State | Persistent by default (50 GB dynamic block volume) until `sbx rm` |
| Project config | Reads `.devcontainer/devcontainer.json` and `Dockerfile` from the project |
| Supported agents | Claude Code, Cursor, Gemini, OpenCode, Codex, Copilot, Docker Agent |
| MCP | Native MCP catalog support |
| Cost | Free for local/individual use; paid tiers add governance/audit |

**Server vs. workstation:** `sbx` is not workstation-only. It runs on any
Linux host with KVM enabled (VT-x/AMD-V), including the Cloudlab VPS.
Installation is via the `docker-sbx` package from the Docker repository plus
KVM group membership for the deploy user.

**Important caveat for the Homelab sandbox:** the Homelab agent *must not* be
given the host Docker socket (`/var/run/docker.sock`). Inside a sandbox the
agent can have its own isolated Docker daemon, but mounting the host socket
would void the isolation. For Homelab work that needs to drive the host's
Docker stack, the agent should generate Ansible playbooks or Compose files and
execute them via a narrow, audited path (e.g. `ansible-playbook` over SSH or a
dedicated deployment user), not by directly manipulating the host daemon.

---

### 3. `devcontainer.json` is the right standard, but not the whole solution

`devcontainer.json` is an open industry standard maintained by the Development
Containers Working Group. It is supported by VS Code, Cursor, JetBrains,
GitHub Codespaces, GitLab Remote Development, and the `@devcontainers/cli`.

**Where it fits:**

- Defines the developer environment: base image, extensions, mounts,
  environment variables, ports, lifecycle scripts.
- Docker AI Sandbox natively reads `.devcontainer/devcontainer.json` and the
  referenced `Dockerfile` to build the agent environment.
- It is the existing source of truth for the Codespaces workflow (ADR 14/17).

**Where it does not fit:**

- A headless OpenCode server does not need VS Code extensions or IDE settings.
- A server container should be described by a **Dockerfile + Compose file**,
  not by a `devcontainer.json` wrapped around an editor.
- Per-project *sandbox* customization can still use `.devcontainer/`, but the
  *server* image should be a thin custom layer over the official OpenCode
  image.

**Recommended split:**

| Layer | File | Purpose |
|-------|------|---------|
| Server runtime | `docker/opencode-server/Dockerfile` | Extends `ghcr.io/anomalyco/opencode` or `docker/sandbox-templates:opencode` with common server tooling |
| Project sandbox | `Homelab/.devcontainer/` / `Prospera/.devcontainer/` | Per-project tools invoked inside the agent sandbox |
| Compose orchestration | `docker/opencode-server/docker-compose.yml` | Defines persistent server containers, networks, volumes, Caddy labels |

---

### 4. Project code reaches the sandbox through workspace mounts or `--clone`

Docker Sandboxes offer two code-access models:

| Mode | Command | Use case |
|------|---------|----------|
| Direct workspace mount | `sbx run opencode ~/my-project` | Agent edits files directly on the host filesystem |
| Clone into sandbox | `sbx run opencode --clone https://github.com/user/repo.git` | Agent works in an isolated Git clone; changes are fetched back |

For a long-lived OpenCode server the equivalent is:

- bind-mount a host directory (e.g. `/home/user/projects:/workspace`) into the
  container, or
- use a named Docker volume for repositories and let the agent clone on demand.

Because OpenCode already has built-in **Git worktree** support (both in the
Desktop GUI and via the `opencode-worktree` / `ocx` plugin for CLI), the
preferred pattern for parallel work is:

```bash
# On the host
git worktree add ../homelab-task-1 feature/task-1
sbx run opencode ../homelab-task-1
```

or, for the persistent server:

```bash
# Inside the OpenCode container / web UI
git worktree add /workspace/homelab-task-1 feature/task-1
```

Each worktree gets an isolated working directory while sharing the `.git`
object store, saving disk space and avoiding checkout conflicts.

---

### 5. Long-lived OpenCode containers are possible but need deliberate persistence

Docker Sandboxes are short-lived by design. For a persistent web server the
model switches to a **Compose-managed container** running `opencode serve` or
`opencode web`:

```yaml
services:
  opencode-homelab:
    image: opencode-server:latest
    container_name: opencode-homelab
    restart: unless-stopped
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    volumes:
      - opencode_homelab_data:/root/.local/share/opencode
      - opencode_homelab_state:/root/.local/state/opencode
      - opencode_homelab_config:/root/.config/opencode
      - /home/user/projects:/workspace
    networks:
      - opencode_net
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
```

Key persistence points:

| Path in container | Contents | Must persist? |
|-------------------|----------|---------------|
| `~/.local/share/opencode/` | SQLite DB (`opencode.db`), WAL, snapshots, repos, tool output | Yes |
| `~/.local/state/opencode/` | Model config, prompt history, session locks | Yes |
| `~/.config/opencode/` | `opencode.jsonc`, MCP packages | Yes |
| `~/.cache/opencode/` | Model registry, downloaded binaries | Optional (can rebuild) |
| `/workspace` | Git repositories | Yes, via bind-mount or named volume |

If running inside `sbx` for short tasks, state persists on the sandbox block
volume until `sbx rm`. For the server container, state persists in named
Docker volumes that can be backed up with Restic (ADR 02) or tarballled to
Azure Blob (runbook 15 pattern).

---

### 6. Dynamic routing through Caddy can be fully automated with the wildcard

The existing Cloudflare Tunnel already terminates `*.example.com` and forwards
to the Homelab Caddy. Adding new OpenCode instances should not require editing
Tunnel config or DNS.

**Recommended target architecture:**

```text
Cloudflare Edge (*.example.com)
        │
        ▼
┌──────────────────┐
│  cloudflared     │  (connected to both mgmt_net and opencode_net)
└────────┬─────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌─────────┐ ┌──────────────┐
│ caddy   │ │ caddy-opencode│  (dedicated ingress for agent traffic)
│ (main)  │ │ (:80, opencode_net only)
└────┬────┘ └───────┬──────┘
     │              │
     ▼              ▼
 Portainer    opencode-homelab
 other mgmt   opencode-prospera
 services     future sandboxes
```

**Why a dedicated `caddy-opencode`?**

- Agent containers live in a separate Docker network (`opencode_net`) from
  infrastructure services (`mgmt_net`).
- A compromised agent cannot scan or reach Portainer, databases, or the main
  ingress from inside the Docker network.
- The main Caddy config stays clean; OpenCode routing is one wildcard rule.
- Operational independence — breaking the main Caddy does not break agents.

**Cloudflare Tunnel config (`config.yml`):**

```yaml
tunnel: <tunnel-id>
credentials-file: /home/nonroot/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: "*-oc.example.com"
    service: http://caddy-opencode:80
  - hostname: "*.example.com"
    service: http://caddy-main:80
  - service: http_status:404
```

**`caddy-opencode` Caddyfile:**

```caddy
:80 {
    @opencode expression `{labels.2}.endsWith("-oc")`

    handle @opencode {
        reverse_proxy http://opencode-{labels.2}:8080 {
            header_up Host {http.request.host}
        }
    }

    handle {
        respond "OpenCode proxy — instance not found." 404
    }
}
```

**How a new instance is added:**

```yaml
# docker/opencode-prospera/docker-compose.yml
services:
  opencode-prospera:
    image: opencode-server:latest
    container_name: opencode-prospera
    restart: unless-stopped
    networks:
      - opencode_net
    volumes:
      - opencode_prospera_data:/root/.local/share/opencode
      - /home/user/projects/prospera:/workspace

networks:
  opencode_net:
    external: true
```

Run `docker compose up -d`. Because the container name matches
`opencode-prospera`, `prospera-oc.example.com` resolves automatically through
the wildcard rule.

**No Caddy Docker Proxy required** in this design. The official Caddy image
handles the wildcard statically; naming discipline (`opencode-<name>`)
provides the dynamic mapping.

---

### 7. Security zones should be separated at the network layer

The threads reinforced a layered security model:

| Zone | Members | Network | Trust level |
|------|---------|---------|-------------|
| Management | Caddy-main, Portainer, Cloudflared, DNSMasq, monitoring | `mgmt_net` | High — infrastructure control plane |
| Agents | `opencode-homelab`, `opencode-prospera`, future sandboxes | `opencode_net` | Medium — runs arbitrary generated code |
| External | Cloudflare edge, public internet | — | Untrusted |

Rules:

- `cloudflared` is the only container attached to both networks; it forwards
  traffic but does not route between networks.
- Agent containers have no access to `mgmt_net`.
- The host Docker socket is **never** mounted into an agent container.
- Secrets are injected via environment variables sourced from a vault or
  `.env` file, not baked into images.
- Each instance has its own named volumes so `docker compose down -v` on one
  project does not touch another.

---

### 8. Ansible can deploy and govern the entire stack

Docker Sandboxes and the OpenCode server containers can both be managed by the
existing Ansible roles:

| Task | Ansible approach |
|------|------------------|
| Install `docker-sbx` package | `ansible.builtin.apt: name=docker-sbx state=present` |
| Add deploy user to `kvm` group | `ansible.builtin.user: groups=kvm append=yes` |
| Create `opencode_net` and `mgmt_net` | `community.docker.docker_network` |
| Deploy `caddy-opencode` | New role `docker_opencode_ingress` |
| Deploy per-project OpenCode instances | New role `docker_opencode_instance` parameterized by project name |
| Configure governance policy | Template `/etc/docker-sbx/config.json` (mode `0644`, owned by root) |

A governance file for `docker-sbx` might look like:

```json
{
  "allowedOrgs": ["my-docker-hub-org"],
  "adminEmail": "admin@example.com",
  "defaultNetworkPolicy": "balanced"
}
```

`sbx login` is an interactive OAuth/Device Code flow, so it is best performed
once manually after the Ansible playbook runs. API keys can then be injected
securely:

```bash
sbx secret set -g openai
```

For automation, Ansible Vault-encrypted variables can be piped through the CLI
with `no_log: true`.

---

## Decisions reached

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Two (or more) per-project OpenCode server instances** instead of one shared instance | Different criticality, tooling, secrets, and stability needs for Homelab vs Prospera |
| 2 | **Run on Cloudlab**, not on the M910q production host | Keeps production host focused; Cloudlab is already Ansible-managed and paid for |
| 3 | **Use Docker AI Sandboxes (`sbx`) for short agent tasks** and **Compose-managed containers for long-lived server instances** | Sandboxes give strongest isolation; containers give persistence and server mode |
| 4 | **Base the server image on the official OpenCode image** (`ghcr.io/anomalyco/opencode` or `docker/sandbox-templates:opencode`) and add a thin custom Dockerfile for project tooling | Avoids bloated devcontainer-derived images; clean separation of runtime vs tools |
| 5 | **Keep `.devcontainer/` in each repo** for Codespaces and sandbox customization, but use a separate Dockerfile for the headless server | `devcontainer.json` is IDE-oriented; server needs are different |
| 6 | **Expose instances via `*-oc.example.com` wildcard** routed through a **dedicated `caddy-opencode` ingress** | Reuses existing Cloudflare Tunnel wildcard; isolates agent traffic from infrastructure network |
| 7 | **Place all OpenCode containers in a dedicated Docker network (`opencode_net`)** separate from `mgmt_net` | Limits blast radius of a compromised agent |
| 8 | **Use Git worktrees for parallel agent tasks** inside each instance | Lightweight isolation of working directories without full clones |
| 9 | **Persist session state in named Docker volumes** and back them up with Restic / Azure Blob | Aligns with ADR 02 and runbook 15 |
| 10 | **Never mount the host Docker socket into an agent container** | Would nullify sandbox isolation |

---

## Alternatives considered

| Option | Verdict | Reason |
|--------|---------|--------|
| Single shared OpenCode instance for all projects | Rejected | Mixes financial secrets with infra secrets; shared failure domain; conflicting toolchains |
| Run OpenCode directly on the host as a `systemd` service | Rejected | No sandbox isolation; agent has host filesystem, SSH keys, Docker socket access |
| Host OpenCode on the M910q | Rejected for now | M910q is the production host; Cloudlab is the designated playground |
| Use Caddy Docker Proxy for dynamic routing | Rejected | Adds a custom Caddy build and label complexity; static wildcard rule is simpler and uses the official image |
| One Caddy instance for everything | Rejected | Would place agent traffic and management traffic in the same network, reducing isolation |
| Use `devcontainer.json` as the server image source | Rejected | Carries IDE-specific weight irrelevant for a headless server |
| Continue using Codespaces as the primary OpenCode host | Rejected | Codespaces suspend after idle timeout and cannot run persistent daemons economically (Research 20) |

---

## Target architecture blueprint

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                              Cloudlab VPS                                │
│  (Ubuntu 24.04, Ansible-managed, Docker, KVM enabled)                   │
│                                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────────────┐ │
│  │ cloudflared │──│ caddy-main   │  │ caddy-opencode  (opencode_net)  │ │
│  │  (both nets)│  │  (mgmt_net)  │  │  :80, wildcard routing          │ │
│  └──────┬──────┘  └──────┬───────┘  └────────────┬────────────────────┘ │
│         │                │                        │                      │
│         │         ┌──────┴───────┐    ┌───────────┴────────────┐         │
│         │         │  Portainer   │    │  opencode-homelab      │         │
│         │         │  monitoring  │    │  opencode-prospera     │         │
│         │         │  other mgmt  │    │  (future sandboxes)    │         │
│         │         └──────────────┘    └────────────────────────┘         │
│         │                                                                 │
│  ┌──────┴─────────────────────────────────────────────────────────┐      │
│  │  named volumes: opencode_homelab_data, opencode_prospera_data   │      │
│  │  bind mounts:   /home/user/projects/homelab → /workspace        │      │
│  │                 /home/user/projects/prospera → /workspace       │      │
│  └─────────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                    Cloudflare Edge (*.example.com)
                                │
              ┌─────────────────┴─────────────────┐
              ▼                                   ▼
      homelab-oc.example.com            prospera-oc.example.com
```

**Instance naming contract:**

| Subdomain | Container name | Network | Project workspace |
|-----------|----------------|---------|-------------------|
| `homelab-oc.example.com` | `opencode-homelab` | `opencode_net` | `/workspace/homelab` |
| `prospera-oc.example.com` | `opencode-prospera` | `opencode_net` | `/workspace/prospera` |
| `<name>-oc.example.com` | `opencode-<name>` | `opencode_net` | `/workspace/<name>` |

---

## Implementation sketch

### New files and roles

| Path | Purpose |
|------|---------|
| `ansible/roles/docker_opencode_ingress/` | Deploys `caddy-opencode` and the `opencode_net` network |
| `ansible/roles/docker_opencode_instance/` | Parameterized role that deploys one OpenCode server instance |
| `ansible/inventory.ini` | Add `opencode_instances` group or host vars |
| `docker/opencode-server/Dockerfile` | Common server image extending official OpenCode image |
| `docker/opencode-server/docker-compose.yml` | Optional reference compose for the base server |
| `docker/opencode-homelab/docker-compose.yml` | Homelab instance |
| `docker/opencode-prospera/docker-compose.yml` | Prospera instance |
| `.env.opencode.example` | Example environment variables (secrets are placeholders) |

### Dockerfile template

```dockerfile
FROM ghcr.io/anomalyco/opencode:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    ansible \
    ansible-lint \
    curl \
    git \
    jq \
    openssh-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Bicep
RUN curl -fsSL -o /usr/local/bin/bicep \
    https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64 \
    && chmod +x /usr/local/bin/bicep

EXPOSE 8080
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
```

### Ansible variables (host_vars/cloudlab.yml)

```yaml
opencode_instances:
  - name: homelab
    subdomain: homelab-oc
    workspace_host_path: /home/user/projects/homelab
  - name: prospera
    subdomain: prospera-oc
    workspace_host_path: /home/user/projects/prospera
```

---

## Open questions

1. **Official image internals.** Does `ghcr.io/anomalyco/opencode:latest` use
   a Debian/Ubuntu base with `apt`, or is it a minimal/distroless image that
   requires a multi-stage build?
2. **OpenCode server MCP behavior.** Does `opencode serve`/`opencode web`
   support local stdio MCP servers (e.g. Azure MCP via `npx`) inside the
   container, or only remote HTTP MCP servers?
3. **Desktop app remote attach.** Can the OpenCode Desktop app connect to a
   remote server through Caddy + Cloudflare Tunnel, or is the web UI the only
   remote option?
4. **Authentication at the edge.** Should the `caddy-opencode` ingress add
   basic auth in front of OpenCode, or should OpenCode's own
   `OPENCODE_SERVER_PASSWORD` be the single gate?
5. **Backup granularity.** Should each instance's named volumes be backed up
   separately (Prospera more frequently) or together as one Restic snapshot?
6. **Host Docker access for Homelab agent.** When the agent needs to affect
   the host Docker stack, is the correct path (a) generate files and run
   `ansible-playbook` via SSH, (b) a narrow `docker` deployment user with
   socket access on a separate socket, or (c) avoid it entirely and keep
   sandbox work as dry-run/syntax validation?
7. **`sbx` vs Compose server interplay.** Will short `sbx run` tasks and the
   long-lived server share the same OpenCode state (SQLite DB), or are they
   separate runtime models?
8. **Cloudflare Tunnel wildcard precedence.** The `*-oc.example.com` rule must
   appear before the `*.example.com` rule in `config.yml`; document and test
   this ordering.

---

## References

- [ADR 17 — Adopt OpenCode](../decisions/17-adopt-opencode.md) (the decision this research supplements)
- [Research 20 — OpenCode Hosting: Codespaces vs Homelab/Cloudlab](20-opencode-hosting-codespaces-vs-homelab.md)
- [Runbook 15 — OpenCode Session Persistence + Backup in Codespaces](../runbooks/15-opencode-session-persistence.md)
- [ADR 02 — Backup Strategy (Restic + Azure Blob)](../decisions/02-backup-strategy-restic-blob.md)
- [ADR 07 — Reverse Proxy (Caddy)](../decisions/07-reverse-proxy-caddy.md)
- [ADR 08 — Remote Access (Cloudflare Tunnel)](../decisions/08-remote-access-cloudflare-tunnel.md)
- [ADR 13 — VPS Playground (Cloudlab)](../decisions/13-vps-playground.md)
- Docker AI Sandboxes docs: https://docs.docker.com/ai/sandboxes/
- Docker OpenCode Agent docs: https://docs.docker.com/ai/sandboxes/agents/opencode/
