# Infisical vs Azure Key Vault for OpenCode Secret Management

**Date:** 2026‑07‑11
**Source:** Web research (Infisical docs, Microsoft Learn)

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
- Requires a Postgres database (can run in the same Compose file).
- Supports SMTP for email, but optional for local-only use.
- Web UI, CLI, SDKs, and REST API are all available in the self-hosted edition.
- Dynamic secrets, secret rotation, and secret scanning are enterprise/paid
  features; static secret CRUD and project RBAC are open-source.

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

Infisical is a strong fallback because its deployment model (Docker Compose,
official Ansible collection, project/environment separation) aligns well with
Homelab conventions. It can be introduced later without changing the overall
OpenCode architecture.
