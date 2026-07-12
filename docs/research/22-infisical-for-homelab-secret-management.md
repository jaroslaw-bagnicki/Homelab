# Infisical for Homelab Secret Management: Evaluation, Deployment, and OpenCode Integration

**Date:** 2026‑07‑11  
**Updated:** 2026‑07‑12  
**Source:** Web research (Infisical docs, Microsoft Learn) and OpenCode MiMo V2.5 research thread at https://opncd.ai/share/i6qtTYlZ (re-read same day to capture additional API, plugin, and agent-mode credential threads)

---

## Why compare them?

ADR 18 currently chooses Azure Key Vault as the source of truth for OpenCode
instance secrets. Azure Key Vault is already used for the Codespaces service
principal and Cloudflare tunnel token (ADR 16, ADR 19), so it is the path of
least resistance. However, it is a cloud service bound to an Azure subscription
and an Entra ID tenant. This note evaluates **Infisical** as a self-hosted
alternative that offers project/workload separation and avoids a cloud
dependency for the secret backend.

---

## Infisical overview

Infisical is an open-source secret management platform. It can be used as a
managed SaaS or self-hosted via Docker, Docker Compose, Kubernetes (Helm), or a
Linux package. For the Homelab context, self-hosted Docker Compose is the
relevant deployment option.

### Workload separation model

| Concept | Purpose |
|---|---|
| **Organization** | Top-level tenant. One per Homelab estate. |
| **Project** | Maps cleanly to a workload (e.g. `opencode-homelab`, `opencode-prospera`). |
| **Environment** | Standard `dev` / `staging` / `prod` slices inside a project. |
| **Folder / path** | Optional grouping inside an environment (`/`, `/db`, `/api`). |
| **Identity** | Machine identity scoped to a project with RBAC. Supports Universal Auth, OIDC, LDAP, and token auth. |

This model matches ADR 18’s requirement that Homelab and Prospera secrets must
never mix. Each OpenCode instance would receive only its own project’s secrets.

### Self-hosting basics

- Official Docker Compose template available.
- Requires **Postgres** and **Redis** (both can run in the same Compose file).
  The thread clarifies this explicitly; the single Docker image needs external
  Postgres and Redis.
- Required base environment variables:
  - `ENCRYPTION_KEY`
  - `AUTH_SECRET`
  - `DB_CONNECTION_URI`
  - `REDIS_URL`
  - `SITE_URL`
- Minimum hardware is modest: Raspberry Pi 4, mini PC, NAS with Docker support,
  or small VPS.
- Supports SMTP for email, but optional for local-only use.
- Web UI, CLI, SDKs, and REST API are all available in the self-hosted edition.
- Dynamic secrets, secret rotation, and secret scanning are enterprise/paid
  features; static secret CRUD and project RBAC are open-source.

### Machine identities and Docker container RBAC

Infisical supports **Machine Identities** for workload authentication. For
Docker containers, the typical flow is:

1. Create one Machine Identity per container/service in the Infisical dashboard.
2. Configure **Universal Auth** (Client ID + Client Secret) for that identity.
3. Assign roles at the project level with scoped permissions (project,
   environment, and folder/path).
4. At container startup, authenticate with the Infisical CLI:
   ```dockerfile
   CMD ["infisical", "run", "--projectId", "<id>", "--", "npm", "start"]
   ```
5. Pass credentials via environment variables:
   ```bash
   docker run \
     -e INFISICAL_MACHINE_CLIENT_ID=<client-id> \
     -e INFISICAL_MACHINE_CLIENT_SECRET=<client-secret> \
     your-image
   ```

**RBAC scoping options:**

- **Project-level** — identity can access only assigned project(s).
- **Environment-level** — restrict to specific environments (dev, staging, prod).
- **Path-level** — restrict to specific folders such as `/database`.
- **Custom roles** — define exact permissions (read-only, read-write, etc.).

Other auth methods include Kubernetes Auth, AWS/GCP/Azure workload identity,
and OIDC Auth. This gives per-container identity with least-privilege access.

### REST API exposure inside Docker networks

The self-hosted Infisical container exposes a REST API that other containers in
the same Docker network can consume. Operational defaults from the thread:

- **Default port:** `8080` (configurable via `PORT`).
- **Bind address:** set `HOST=0.0.0.0` to listen on all interfaces; the default
  is localhost-only and would not be reachable from other containers.
- **Internal URL:** `http://infisical:8080` when the service is named
  `infisical` in the same Compose network.
- **Consumption options:** Infisical CLI, language SDKs, or direct REST calls
  such as `curl http://infisical:8080/api/v1/secrets`.
- **Authentication:** Machine Identities via Universal Auth (Client ID +
  Client Secret) to obtain short-lived access tokens.

Example Compose snippet:

```yaml
services:
  infisical:
    image: infisical/infisical:latest
    environment:
      - HOST=0.0.0.0
      - PORT=8080
    networks:
      - homelab

  my-app:
    image: my-app
    environment:
      - INFISICAL_API_URL=http://infisical:8080
    networks:
      - homelab

networks:
  homelab:
```

This means Infisical can sit on the same internal Docker network as the
workloads it serves, avoiding the need to expose the secret API to the public
internet.

### Ansible integration

Infisical provides an official Ansible collection (`infisical.vault`) on Galaxy:

- `infisical.vault.login` — authenticate once and cache session data.
- `infisical.vault.read_secrets` — read secrets as a dictionary or raw list.
- `infisical.vault.create_secret`, `update_secret`, `delete_secret` — full CRUD.
- Supports **Universal Auth** (client id + client secret) and **Token Auth**,
  among others.
- Requires Python ≥ 3.7 and `infisicalsdk`.

This is comparable to the `azure.azcollection.azure_keyvault_secret` lookup
used today, with the extra step of maintaining a self-hosted service.

### OpenCode plugin integration concept

The thread also explored whether an OpenCode plugin should integrate with
Infisical. OpenCode's plugin system supports custom tools, `shell.env` hooks,
and 25+ lifecycle events. A plugin could expose tools such as:

| Feature | Hook/Method | Value |
|---|---|---|
| `infisical_get_secret` | Custom tool | AI fetches a secret on-demand |
| `infisical_list_secrets` | Custom tool | Browse available project secrets |
| Env var injection | `shell.env` | Auto-inject secrets into shell commands |
| Secret validation | `tool.execute.before` | Verify required secrets exist before running |
| Project auto-switch | `session.created` | Detect context and switch Infisical project |

Potential use cases include OpenCode fetching `DB_PASSWORD` while writing code,
injecting secrets during `docker compose up` instead of using `.env` files,
syncing secrets for new project setup, and validating required secrets before
deployment.

Trade-offs:

- **Pros:** secrets never on disk in plaintext; centralized management with
  audit; per-session credential scoping; works with a self-hosted Infisical
  instance.
- **Cons:** adds dependency on Infisical availability; requires securely
  managing the Machine Identity's own credentials (secret-zero problem);
  plugin complexity for what may be a small credential set.

---

## Azure Key Vault overview

Azure Key Vault is the existing cloud secret store in the Homelab estate.

### Workload separation model

| Concept | Purpose |
|---|---|
| **Vault** | One per resource group / lifecycle boundary. Currently `homelab-bysxdb-kv`. |
| **RBAC** | Role assignments at vault or secret scope (`Key Vault Secrets User`, `Key Vault Secrets Officer`). |
| **Secret name prefix / tags** | Convention used to separate workloads within one vault (e.g. `opencode-homelab-...`, `opencode-prospera-...`). |

There is no native “project” boundary inside a vault. Separation is enforced by
RBAC and naming convention, not by a first-class container. To get true
isolation, multiple vaults are required, which increases Azure surface area and
cost.

### Ansible integration

- `azure.azcollection.azure_keyvault_secret` lookup.
- Requires `azure-identity` and `azure-keyvault-secrets` Python packages.
- Authentication relies on the Ansible controller’s Azure identity (service
  principal, managed identity, or CLI login).

### Operational characteristics

- Fully managed; no host to patch or back up.
- Integrated with Azure audit logs and RBAC.
- Requires Azure subscription and network path to Azure APIs.
- Cost is negligible at Homelab scale.

---

## Side-by-side comparison

| Capability | Infisical self-hosted | Azure Key Vault |
|---|---|---|
| **Hosting model** | Self-hosted container on Cloudlab/Homelab | Managed Azure service |
| **Project/workload separation** | First-class projects + environments | Naming convention + RBAC; multiple vaults for hard isolation |
| **Ansible support** | Official `infisical.vault` collection with lookup + modules | Official `azure.azcollection.azure_keyvault_secret` lookup |
| **Authentication to Ansible** | Universal Auth / token (client id + secret) | Azure service principal or managed identity |
| **Cost at Homelab scale** | Runs on existing Cloudlab VPS; only backup/Postgres overhead | ~$0 at low usage |
| **Availability risk** | One more service to keep running and restore after failure | Azure dependency; no local restore needed |
| **Audit / versioning** | Built-in versioning and activity logs | Built-in versioning and Azure Monitor logs |
| **Dynamic secrets** | Enterprise feature | Native certificates, keys, and some dynamic secret patterns |
| **Backup responsibility** | Self-managed Postgres backups | Microsoft-managed redundancy |
| **Secrets never leave home network** | Yes, if not exposed to internet | No, stored in Azure |
| **Fits existing Homelab stack** | New service, but Docker Compose friendly | Already in use |

---

## Trade-offs for OpenCode

### Why Infisical could fit

- **Self-contained.** Secrets stay on Cloudlab/Homelab alongside the OpenCode
  instances that consume them. No Azure network dependency at deploy time.
- **Project boundary matches ADR 18.** One Infisical project per OpenCode
  instance is a natural mapping.
- **Compose-friendly deployment.** Can be deployed with the same Ansible +
  Docker Compose patterns already used for other Homelab services.
- **Lower long-term vendor lock-in** if the goal is to reduce Azure surface.

### Why Azure Key Vault is probably better for now

- **Already operational.** ADR 16 set up the vault and service principal; ADR 19
  already uses the Ansible lookup for the Cloudflare tunnel token.
- **Less operational overhead.** No Postgres container to back up, patch, and
  monitor.
- **Same trust boundary.** The OpenCode instances themselves run on Cloudlab
  and are exposed through Cloudflare Tunnel — they are already internet-facing
  in a sense. Keeping the secret backend in Azure is not a meaningful increase
  in cloud dependency.
- **No additional migration work.** Continuing with Key Vault avoids a
  two-system transition.

---

## Validation notes from the OpenCode thread

The research thread confirmed several operational points relevant to a Homelab
deployment:

1. **Self-hosting is viable on modest hardware** — a mini PC or small VPS is
   sufficient, matching the existing Cloudlab VPS footprint.
2. **Redis is a hard dependency** alongside Postgres for the Docker image.
   This should be included in any Compose file or Ansible role.
3. **Project-level isolation is first-class**, not a naming convention. This
   directly satisfies the requirement that different OpenCode instances (or
   other workloads) must not share secret scope.
4. **Docker containers authenticate cleanly** via Machine Identities using
   Universal Auth. The `INFISICAL_MACHINE_CLIENT_ID` and
   `INFISICAL_MACHINE_CLIENT_SECRET` pattern fits the existing Homelab pattern
   of passing secrets into containers via environment variables.
5. **Path-level RBAC** allows a single project to host multiple secret groups
   (for example `/database`, `/redis`, `/smtp`) without exposing all secrets to
   every consumer.
6. **REST API is reachable on the internal Docker network** once `HOST=0.0.0.0`
   is set, so workloads can pull secrets without public exposure.
7. **OpenCode plugin integration is feasible** via custom tools and the
   `shell.env` hook, but the value depends on credential count and rotation
   frequency.

## Recommendation

**Keep Azure Key Vault as the initial secret backend** for OpenCode per ADR 18.
It is already integrated, managed, and sufficient for two-project separation
via naming convention and RBAC.

**Re-evaluate Infisical if** any of the following become true:

1. The number of OpenCode instances or projects grows beyond two, making vault
   naming conventions unwieldy.
2. A hard requirement emerges that secrets must not leave the self-hosted
   perimeter.
3. Azure cost or operational concerns outweigh the convenience of a managed
   service.
4. Dynamic secrets or richer project-level RBAC become necessary.

### Agent-mode credential provisioning concept

A later part of the thread explored using Infisical to feed **Azure service
principal credentials** and **GitHub SSH keys** into the OpenCode agent in
agent mode. This is feasible and conceptually attractive, but security-heavy.

**Credential patterns:**

- Azure SP: standard env vars `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
  `AZURE_CLIENT_SECRET`.
- GitHub: private SSH key loaded into `ssh-agent` via `SSH_AUTH_SOCK` so the
  key never touches disk.

**Conceptual flow:**

1. OpenCode plugin calls Infisical SDK using a Machine Identity.
2. Azure SP secrets are passed into the `shell.env` hook.
3. SSH private keys are loaded into `ssh-agent` (not written to files).
4. Agent runs `az login --service-principal`, `terraform apply`, or `git`
   commands with credentials available only in memory.

**Security considerations from the thread:**

- **Credential exposure in tool output.** If `infisical_get_secret` returns the
  raw value, it may leak into conversation history, shared sessions, or logs.
  Tools should return confirmation messages and push values directly to env
  vars or `ssh-agent`.
- **Agent mode privilege.** Any command the agent runs can read env vars.
  Scope credentials to specific projects/commands rather than globally.
- **SSH key lifecycle.** Keys loaded into `ssh-agent` persist until removed.
  Consider `ssh-add -x` or time-limited keys, and use Infisical rotation.
- **Multi-project scoping.** Options include a single Infisical project with
  folder paths (`/azure/*`, `/github/*`), multiple projects per workload, or
  per-directory project mapping in plugin config.

**Verdict:** feasible and useful for dynamic or rotating credentials across
many services. For a static set of 2–3 credentials, the simpler Infisical CLI
approach (`eval "$(infisical export)"` in shell init, plus SSH agent
forwarding) is likely enough.

---

## Re-evaluation trigger list

Consider moving from Azure Key Vault to Infisical if any of the following
become true:

1. The number of OpenCode instances or projects grows beyond two, making vault
   naming conventions unwieldy.
2. A hard requirement emerges that secrets must not leave the self-hosted
   perimeter.
3. Azure cost or operational concerns outweigh the convenience of a managed
   service.
4. Dynamic secrets or richer project-level RBAC become necessary.
5. You want workloads on the internal Docker network to fetch secrets from a
   local API rather than calling Azure.
6. You want to experiment with an OpenCode plugin that sources secrets from a
   self-hosted store.

## Recommendation

**Keep Azure Key Vault as the initial secret backend** for OpenCode per ADR 18.
It is already integrated, managed, and sufficient for two-project separation
via naming convention and RBAC.

Infisical is a strong fallback because its deployment model (Docker Compose,
official Ansible collection, project/environment separation) aligns well with
Homelab conventions. It can be introduced later without changing the overall
OpenCode architecture.
