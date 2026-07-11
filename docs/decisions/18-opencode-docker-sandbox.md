# Host OpenCode Server Instances on Cloudlab

**Date:** 2026-07-11
**Status:** Proposed

---

## Context

ADR 17 adopted OpenCode as the primary agentic development tool, initially
deployed in GitHub Codespaces. That decision explicitly scoped out two areas:

- **Background automations / scheduled agent tasks** — not investigated
- **Cross-machine session sharing** — local to one Codespace

This ADR builds on two research files: [Research 20](../research/20-opencode-hosting-codespaces-vs-homelab.md),
which compared Codespaces and Cloudlab/Homelab hosting, and [Research 21](../research/21-opencode-sandboxed-homelab-architecture.md),
which explored instance topology, isolation primitives, and ingress design.

[Research 20](../research/20-opencode-hosting-codespaces-vs-homelab.md) identified
that Codespaces cannot serve as a persistent OpenCode server: idle timeout
(~30 min), no cron, and the 1:1 repo model block server-mode operation,
multi-project workspaces, scheduled automations, and cross-project backup.

New requirements emerged that reshape the hosting decision:

| Priority | Requirement |
|---|---|
| Must | Persistent server daemon — `opencode web` with HTTP API + WebUI, connectable from OpenCode Desktop App and browser |
| Must | Isolated agent runtime — no direct host filesystem, Docker socket, or SSH-key access |
| Must | Support multiple projects with different toolchains and secrets profiles |
| Must | Project tooling (Ansible, Bicep, .NET, SQL, etc.) available in the agent environment |
| Nice-to-have | Per-project sandbox isolation |

Both the Homelab M910q (ADR 01) and the Contabo Cloudlab VPS (ADR 13) run
Ubuntu 24.04 with Docker and Caddy, managed via Ansible.

[Research 21](../research/21-opencode-sandboxed-homelab-architecture.md) then
explored whether to run one shared or multiple per-project instances, what
isolation primitive to use, and how to integrate the new instances with the
existing Cloudflare Tunnel + Caddy ingress. This ADR records the settled design.

---

## Decision

**Run per-project OpenCode server instances as Docker Compose containers on
Cloudlab**, managed via Ansible, isolated in a dedicated Docker network, and
exposed through a dedicated Caddy ingress. Codespaces remains an emergency
fallback and occasional GitHub Copilot workspace per ADR 17.

### Key design choices

1. **Per-project instances.** Deploy at least two logical instances from the
   start:
   - `opencode-homelab` for the Homelab project (Ansible, Bicep, Docker)
   - `opencode-prospera` for the Prospera project (.NET, SQL, Azure)

   Homelab is an R&D/experimentation zone; Prospera holds financial data and
   requires higher stability. Sharing one SQLite session database and one
   environment would mix secrets, toolchains, and failure domains.

2. **Cloudlab as primary host.** Cloudlab (Contabo VPS, ADR 13) is the natural
   first target: already Ansible-managed, already paid for, and separate from
   production services on the M910q. The M910q could host the same setup later,
   but is kept focused on production for now.

3. **Docker Compose for the initial deployment.** Standard containers fit the
   existing Homelab stack (ADR 03) and avoid KVM availability questions on the
   Contabo VPS. Docker AI Sandboxes (`sbx`) are deferred to a future
   evaluation once the Compose deployment is stable.

4. **Official image + thin custom Dockerfile.** Base the server image on
   `ghcr.io/anomalyco/opencode` and extend it with project-specific tooling.
   This is cleaner than a `devcontainer.json`-derived image, which carries
   IDE-specific weight irrelevant for a headless server.
   `devcontainer.json` remains the source of truth for Codespaces.

5. **Dedicated `caddy-opencode` ingress.** Agent traffic is routed through a
   separate Caddy instance in the `opencode_net` Docker network. The existing
   `caddy-main` holds the `*.cloud5.ovh` wildcard and proxies
   `*-oc.cloud5.ovh` subdomains to `caddy-opencode`. This keeps management and
   agent traffic in separate networks.

6. **Dynamic wildcard routing.** New instances are exposed automatically by
   following the naming convention `opencode-<name>` ↔ `<name>-oc.cloud5.ovh`.
   No Caddy Docker Proxy or manual DNS edits are required.

7. **No host Docker socket in agent containers.** The Homelab agent applies
   changes via SSH/Ansible, not by directly controlling the host Docker
   daemon. This preserves isolation.

8. **OpenCode built-in authentication.** Protect each instance with
   `OPENCODE_SERVER_PASSWORD`. Caddy basic auth or Cloudflare Access SSO can be
   layered later if needed. Caddy has no native Entra ID support.

9. **Backups out of scope initially.** Session persistence is handled by named
   Docker volumes. Backup strategy will be added as a follow-up once the
   instances are stable.

---

## Consequences

### Positive

- **Clear isolation between projects.** Financial/secrets context never mixes
  with infrastructure experimentation.
- **Fits existing infrastructure.** Ansible, Docker Compose, Caddy, and
  Cloudflare Tunnel patterns already in use.
- **Network segmentation.** Agent containers cannot reach Portainer or other
  management services from inside the Docker network.
- **Incremental path to `sbx`.** Once KVM and `sbx` tooling are verified, the
  Compose services can be replaced or complemented by sandboxes.
- **Remote access from any device.** Browser-based WebUI through Cloudflare
  Tunnel.

### Negative

- **More moving parts than one shared instance.** Two OpenCode containers, two
  sets of named volumes, two passwords, two compose files.
- **No backups at launch.** A host failure before the backup follow-up would
  lose session data.
- **Weaker isolation than `sbx`.** Standard containers share the host kernel;
  the Homelab agent still has SSH access to the host.
- **Authentication is basic password only.** No SSO or audit trail at launch.

### Alternatives Considered

- **Codespaces as server host** — rejected per Research 20. Idle timeout, no
  cron, 1:1 repo model. Cannot meet server mode or background automation
  requirements.
- **Single shared OpenCode instance** — rejected. Mixes Prospera financial
  secrets with Homelab infrastructure secrets and creates a shared failure
  domain.
- **Docker AI Sandboxes (`sbx`) from day one** — deferred. KVM availability on
  Cloudlab is unverified, and `sbx` adds operational complexity before the
  basic server model is proven.
- **Host OpenCode directly on the M910q** — rejected for now. The M910q hosts
  production services; Cloudlab is the designated playground.
- **Host OpenCode as a bare-metal service** — rejected. Ansible-managed host
  service is reproducible, but grants OpenCode full host access (filesystem,
  SSH keys, Docker socket), violating the isolation requirement.
- **Mount host Docker socket into the Homelab container** — rejected. Would
  void isolation; SSH/Ansible already provides a controlled deployment path.
- **Caddy Docker Proxy for dynamic routing** — rejected. Avoids a custom Caddy
  build; static wildcard rules on the official image are sufficient.
- **One Caddy instance for everything** — rejected. Would place agent and
  management traffic in the same network, reducing isolation.
- **`devcontainer.json`-derived image** — rejected in favor of the official
  `ghcr.io/anomalyco/opencode` image. `devcontainer.json` carries VS Code
  extensions, IDE settings, and user-setup logic irrelevant for a headless
  server.

---

## Out of scope

- Backup strategy (will be addressed in a follow-up).
- Docker AI Sandboxes deployment (deferred evaluation).
- Single sign-on / audit logging (basic auth only for now).

---

## References

- [ADR 17 — Adopt OpenCode](17-adopt-opencode.md)
- [ADR 13 — VPS Playground (Cloudlab)](13-vps-playground.md)
- [ADR 08 — Cloudflare Tunnel](08-remote-access-cloudflare-tunnel.md)
- [ADR 07 — Caddy Reverse Proxy](07-reverse-proxy-caddy.md)
- [ADR 03 — Container Strategy](03-container-strategy.md)
- [Research 20 — OpenCode Hosting: Codespaces vs Homelab/Cloudlab](../research/20-opencode-hosting-codespaces-vs-homelab.md)
- [Research 21 — OpenCode Sandboxed Architecture on Homelab](../research/21-opencode-sandboxed-homelab-architecture.md)
