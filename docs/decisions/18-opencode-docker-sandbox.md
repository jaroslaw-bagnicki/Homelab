# Host OpenCode Server Instances on Homelab

**Date:** 2026-07-11
**Status:** Accepted

---

## Context

The Homelab project uses OpenCode (ADR 17) as the primary agentic development tool. OpenCode requires a **persistent server daemon** (`opencode web` with HTTP API + WebUI), **multi-project isolation** (financial-context workloads must not share state with infrastructure-experimentation workloads), and **project-specific toolchains** (the Homelab project uses Ansible/Bicep/Docker; Prospera uses .NET/SQL/Azure).

A dedicated host for OpenCode is needed. The homelab is the production target — the physical server hosts the OpenCode workloads, with per-project instances isolated from each other.

The host-side decision (homelab) is independent of the substrate (Docker Compose, Kubernetes, etc.), which is decided separately.

---

## Decision

**Run per-project OpenCode server instances on the homelab.**

### Key design choices

1. **Container-based isolation (sandboxing).** OpenCode runs in containers, not as bare-metal services. Each instance is a container with its own process, filesystem, network, and resource namespace — isolated from the host and from other instances. The per-project split (item 2) is implemented as per-project containers. Bare-metal services are explicitly rejected (see Alternatives Considered).

2. **Per-project instances.** At least two logical instances from the start:
   - `opencode-homelab` for the Homelab project (Ansible, Bicep, Docker)
   - `opencode-prospera` for the Prospera project (.NET, SQL, Azure)

   Homelab is an R&D/experimentation zone; Prospera holds financial data and requires higher stability. Sharing one SQLite session database and one environment would mix secrets, toolchains, and failure domains.

3. **Authentication: `OPENCODE_SERVER_PASSWORD`** (basic password at launch). Caddy basic auth or Cloudflare Access SSO can be layered later if needed. Caddy has no native Entra ID support.

4. **No host Docker socket in agent containers** (where the substrate exposes one). The Homelab agent applies changes via SSH/Ansible or via the cluster's RBAC, not by directly controlling a host Docker daemon. Preserves isolation.

### What this decision is

- Per-project OpenCode instances on the homelab.

### What this decision is not

- The substrate (Docker Compose, Kubernetes, etc.) — decided in a separate ADR.

---

## Consequences

### Positive

- **Clear isolation between projects.** Financial/secrets context never mixes with infrastructure experimentation.
- **Remote access from any device.** Browser-based WebUI through whatever public ingress the substrate exposes.

### Negative

- **More moving parts than one shared instance.** Multiple OpenCode containers, multiple sets of named volumes, multiple passwords, multiple compose / deployment manifests.
- **No backups at launch.** Session persistence is handled by named volumes or cluster storage. Backup strategy is a follow-up.
- **Weaker isolation than `sbx`.** Standard container isolation, not sandbox-grade. Docker AI Sandboxes (`sbx`) deferred to a future evaluation.
- **Authentication is basic password only at launch.** No SSO or audit trail at the instance level. Caddy basic auth or Cloudflare Access SSO can be layered later.

---

## Alternatives Considered

- **Codespaces as host** — rejected. Idle timeout (~30 min), no cron, 1:1 repo model. Cannot meet server mode or background automation requirements.
- **Single shared OpenCode instance** — rejected. Mixes Prospera financial secrets with Homelab infrastructure secrets and creates a shared failure domain.
- **Docker AI Sandboxes (`sbx`) from day one** — deferred. KVM availability on the homelab is unverified, and `sbx` adds operational complexity before the basic server model is proven.
- **Host OpenCode as a bare-metal service** — rejected. A bare-metal OpenCode service is reproducible, but grants OpenCode full host access (filesystem, SSH keys, Docker socket), violating the isolation requirement.
- **`devcontainer.json`-derived image** — rejected in favor of the official `ghcr.io/anomalyco/opencode` image. `devcontainer.json` carries VS Code extensions, IDE settings, and user-setup logic irrelevant for a headless server.

---

## Out of scope

- Per-project image hierarchy — decided in ADR 21.
- Per-instance identity pattern — decided in ADR 16.
- Per-instance MCP server configuration — tracked in #41.
- Per-instance Azure credential lifecycle — tracked in #40.
- Per-instance GitHub identity — tracked in #43.
- Backup strategy — deferred.
- Docker AI Sandboxes deployment — deferred evaluation.
- Single sign-on / audit logging — deferred.

---

## References

- [ADR 16 — Non-Interactive Agent Workload Identity Pattern](16-gh-codespaces-sp-for-homelab.md)
- [ADR 17 — Adopt OpenCode for Agentic Homelab Development](17-adopt-opencode.md)
- [ADR 21 — Per-Project OpenCode Container Images](21-opencode-instance-images.md)
- [Issue #40 — Provision per-instance Azure service principals](https://github.com/jaroslaw-bagnicki/Homelab/issues/40) (in flight)
- [Issue #41 — Configure MCP servers per instance](https://github.com/jaroslaw-bagnicki/Homelab/issues/41)
- [Issue #43 — Adopt GitHub App as OpenCode identity for GitHub MCP](https://github.com/jaroslaw-bagnicki/Homelab/issues/43)
