# GH Codespaces Service Principal for Homelab

**Date:** 2026-06-28  
**Status:** Implemented

---

## Context

The Opencode evaluation required an Azure-resident identity the agent could use
to call Azure MCP tools from inside a GitHub Codespace. The Codespace is
ephemeral and headless — no interactive browser for `Connect-AzAccount
-UseDeviceAuthentication` to land on — so a non-interactive identity is
required.

While scoping the change it became clear the identity is **not** Opencode-
specific. Any Codespace workload that touches Azure (Opencode today, Ansible
playbooks against Azure tomorrow, future MCP servers, ad-hoc `Az` cmdlets)
needs the same identity. Tool-specific naming would force a rename the first
time the SP is reused.

The existing Bicep-managed Key Vault `homelab-bysxdb-kv` (RBAC-only, no access
policies) already stores project secrets such as `cloudlab-vps-key-priv`. It is
the natural place to persist the SP credentials as the single source of truth,
so the secret is auditable, versioned, and rotatable from one place rather than
buried in GitHub secret history.

## Decision

Establish a dedicated **Service Principal** for the Homelab project's
GitHub Codespaces sessions, scoped to the project's resource group, with the
credentials persisted in the existing Key Vault and forwarded to the dev
container via GitHub Codespaces repository secrets.

### Identity and naming

- **SP display name:** `homelab-codespaces-sp` — project-and-purpose, not
  tool-specific, so future reuse doesn't require a rename
- **KV secret names:** `codespaces-sp-tenant-id`, `codespaces-sp-client-id`,
  `codespaces-sp-client-secret` — kebab-case, matching the existing
  `cloudlab-vps-key-priv` convention in the same vault
- **Codespaces secret names:** `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`,
  `AZURE_CLIENT_SECRET` — these are fixed by the Azure Identity SDK's
  `EnvironmentCredential` contract and cannot be renamed without breaking
  the Azure MCP server's authentication

### Scope and credentials

- **RBAC roles:**
  - `Contributor` on
    `/subscriptions/a8a36bc1-79a7-49fe-9faa-92220103c66f/resourceGroups/homelab-rg`
    — the Homelab project's resource group (control plane). Not
    subscription-wide, not Reader-only. The agent needs to create and
    modify Azure resources inside the project's RG during the Opencode
    evaluation.
  - `Key Vault Secrets User` on
    `homelab-bysxdb-kv` (data plane) — **separate** from the
    control-plane `Contributor` above. Azure RBAC for data plane
    (Key Vault secrets, Storage blobs) is not implied by control-plane
    roles. Without this role, the SP cannot read `cloudlab-vps-key-priv`
    (the SSH key loaded by `profile.ps1`) or any other secret value
    in the vault. Required so the Codespace can pull project secrets
    the same way the interactive `Az` session does.
- **Credential type:** **Client secret** (password credential), not a
  certificate. The Microsoft Graph Bicep extension v1.0 GA does not expose
  the `addPassword` action as a Bicep resource (issue #38 closed as
  "Not planned"), so a Bicep-only path was rejected in favour of the
  simpler Az PowerShell route.
- **Default lifetime:** 365 days; rotated by re-running the same script.

### Bootstrap tool

- **Azure PowerShell only** — `New-AzADServicePrincipal` +
  `New-AzADSpCredential` + `New-AzRoleAssignment` (×2: control plane on
  the RG + data plane on the KV) + `Set-AzKeyVaultSecret`. No Azure CLI
  (project rule from `copilot-instructions.md`: "Always use Az
  PowerShell — never Azure CLI"). No Microsoft Graph SDK install needed —
  the `Az` module's `Az.Resources` and `Az.KeyVault` cmdlets are already
  shipped with the module the dev container installs.
- **Microsoft Graph Bicep extension v1.0** was considered and rejected for
  bootstrap: the extension cannot create a client secret in pure Bicep
  (the Graph API requires the `addPassword` action, which is not exposed
  as a Bicep resource type), so a `Microsoft.Resources/deploymentScripts`
  wrapper around `Add-MgApplicationPassword` would still be required —
  more code, slower execution, no benefit over the Az PowerShell path.
- Script: `scripts/Set-HomelabCodespacesSp.ps1` (PowerShell verb-noun
  convention, matching `Import-SshKey.ps1` and `Get-ArcClientSecret.ps1`).

### MCP transport and runtime

- **Transport:** local stdio (`type: "local"` in `opencode.json`).
  Credentials never leave the Codespace; no Azure-hosted relay.
- **Runtime:** Node.js via `npx -y @azure/mcp@latest server start`.
  Adds the `ghcr.io/devcontainers/features/node:2` feature to the
  dev container; Node is not bundled by the existing `azure-cli` feature.
- **Auth mechanism:** `DefaultAzureCredential` → `EnvironmentCredential`
  reading the three `AZURE_*` env vars. No `--tenant` or `--auth-mode`
  flag exists on the Azure MCP server; authentication is environment-driven.

### PowerShell session

The same SP also authenticates interactive `Az` cmdlets inside the
Codespace. `.devcontainer/config/profile.ps1` uses
`Connect-AzAccount -ServicePrincipal` when the env vars are present,
falling back to `-UseDeviceAuthentication` otherwise. Both flows share
the cached context.

## Consequences

### Positive

- **Single identity for all Codespace Azure workloads** — Opencode today,
  Ansible playbooks tomorrow, future MCP servers and `Az` cmdlets all
  share the same identity and the same RBAC boundary
- **Secret lives in the existing Key Vault** — auditable, versioned
  (KV keeps previous secret values), and rotatable from one place via
  the same script that creates it
- **Codespaces secrets are a thin forwarding layer** — the source of
  truth is the KV; Codespaces secrets are just the operational bridge
  to the container's env vars
- **SP cannot reach outside the homelab project** — RBAC scoped to
  `homelab-rg` only, so even a destructive Opencode command cannot
  touch other subscriptions or RGs
- **Repo rule satisfied** — pure Az PowerShell, no `az` CLI in the
  bootstrap path

### Negative

- **Two copies of the secret exist** — the KV and the Codespaces repo
  secrets. A rotation requires updating both. The KV is the source of
  truth; Codespaces secrets are a manual copy.
- **`Contributor` on `homelab-rg` is destructive** — the SP can create
  and delete resources inside that RG. The Opencode evaluation should
  start with read-only prompts and only enable mutations after a smoke
  test.
- **Codespaces secrets propagate only at container-creation time** —
  rotating the secret requires a Codespace rebuild (not a simple
  restart). This is a Codespaces platform behavior, not something this
  decision can change.
- **`@azure/mcp@latest` pins to latest at spawn time** — a fresh
  release can change behavior mid-eval. Pin to a specific GA version
  (e.g. `@azure/mcp@2.0.0`) if reproducibility matters.

### Alternatives Considered

- **HTTP/remote Azure MCP hosted on Azure Container Apps** — adds
  extra Azure infra (Container App + auth + monitoring), incurs
  network RTT on every tool call, and the SP credentials would have
  to be presented to a remote endpoint over the wire. Rejected as
  over-engineering for the evaluation scope.
- **Docker image runtime for the MCP server**
  (`mcr.microsoft.com/azure-sdk/azure-mcp`) — cleanest isolation but
  pulls a multi-GB image on first MCP use and requires the
  docker-outside-of-docker feature to already be in the container.
  `npx` is faster and lighter for a one-tool scenario.
- **Microsoft Graph Bicep extension for SP creation** — the
  extension is GA v1.0 (July 2025, Bicep v0.36.1+), but it cannot
  create a client secret in pure Bicep. A `deploymentScripts`
  wrapper around `Add-MgApplicationPassword` would work but adds
  ~3× the code of the Az PowerShell path. Rejected.
- **Reader-only RBAC on `homelab-rg`** — safer, but blocks the
  evaluation's mutating-tool prompts. Rejected for the initial scope;
  can be tightened after the evaluation completes.
- **Azure CLI for SP creation (`az ad sp create-for-rbac`)** —
  one-liner but violates the repo rule "Always use Az PowerShell —
  never Azure CLI". Rejected.
- **User-level Codespaces secret** — would scope the SP to a single
  developer account, not the repo. Rejected because the SP is a
  Homelab project asset, reusable by any contributor.
- **One SP per tool** (e.g. `homelab-opencode-sp`,
  `homelab-ansible-sp`) — would create credential-management overhead
  and force a rename the first time a second tool needed the
  identity. Rejected in favour of the project-scoped
  `homelab-codespaces-sp`.

---

> **Reference:** [Runbook 14](../runbooks/14-gh-codespaces-sp-for-homelab.md) — bootstrap, verification, rotation, and troubleshooting.
