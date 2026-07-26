# Non-Interactive Agent Workload Identity Pattern

**Date:** 2026-06-28
**Last revised:** 2026-07-26
**Status:** Implemented

---

## Context

The Homelab project runs multiple **non-interactive agent workloads** — code that calls Azure APIs, manages resources, and drives multi-step workflows without a human in the loop. Examples include:

- The OpenCode server instances on Cloudlab (ADR 18) and the OpenCode session data backup (`Backup-OpencodeData.ps1`)
- Future Kubernetes-resident workloads on the homelab cluster (ADR 22)
- The DR simulation skill (issue #16) when it executes against Azure
- Future MCP servers, ad-hoc `Az` cmdlets in agent sessions, and any other automated Azure work

These workloads share a property: **they cannot use a developer's personal identity**. A personal identity (a developer's interactive `Az` login, a personal PAT) has at least three problems in this context:

1. **No audit trail for the workload** — actions are attributed to the person, not to the workload, making it impossible to answer "what did the homelab-oc instance do at 03:00 last night?"
2. **Inherits the developer's scope** — the workload gains whatever the developer has, which is broader than the workload needs. A workload that should only touch `homelab-rg` could end up with subscription-wide reach.
3. **Tied to the developer's lifecycle** — if the developer leaves, rotates credentials, or revokes their session, the workload stops working.

The pattern this ADR records is the answer: **a non-personal identity per non-interactive agent workload**, scoped with least privilege, persisted independently of any developer's account, rotatable on its own schedule.

### Substrate-dependent identity type

The specific identity type depends on the **deployment substrate** the workload runs on:

- **Docker Compose / Codespaces / bare host workloads** — Service Principal with client_secret persisted in Azure Key Vault, fetched at deploy time, injected as container env vars (the original pattern, in flight for OpenCode on Cloudlab via #40).
- **Kubernetes workloads on the homelab cluster (per ADR 22)** — UAMI Workload Identity per ServiceAccount. No client_secret in the cluster; the Azure SDKs exchange the K8s service-account token for an Entra token at runtime via federated identity credentials.

Both paths land in the same consumer code: the Azure SDKs use `DefaultAzureCredential`, which already includes both `EnvironmentCredential` (for the SP path) and `WorkloadIdentityCredential` (for the UAMI path). The substrate is invisible to the workload.

### Why the substrate split exists

A Service Principal with a client_secret is the right identity primitive for a workload that lives in a container or on a host — the secret is fetched at deploy time and lives in the workload's env vars. A K8s ServiceAccount, by contrast, can be federated to a UAMI via the OIDC trust between the cluster and Entra ID; the workload's token is short-lived, the UAMI's RBAC is explicit, and no secret material lives in the cluster. Using a SP in K8s would mean putting a long-lived client_secret in a Secret or env var — defeating the platform's secret-management primitives. Using a UAMI in Docker Compose would mean standing up OIDC trust for a non-K8s workload — over-engineered. The split is substrate-driven, not preference-driven.

### History of the pattern

The pattern was originally scoped to the Codespaces workflow (one project-wide SP for any Codespaces-resident workload that touched Azure). That specific SP — `homelab-codespaces-sp` — was never actually created: Codespaces became an emergency-only environment (per ADR 17's narrower scope) and the SP-for-Codespaces implementation was deferred indefinitely. The **pattern** itself was sound and was re-applied to the OpenCode on Cloudlab workload via #40, where the first per-instance SPs (`opencode-agent-sp-homelab` and the deferred `opencode-agent-sp-prospera`) are in flight. When the homelab k3s cluster lands (ADR 22), the pattern is replaced for cluster-resident workloads by UAMI Workload Identity per ServiceAccount.

---

## Decision

**Adopt a non-personal identity per non-interactive agent workload. The specific identity type is substrate-driven:**

| Substrate | Identity type | Secret material | Bootstrap tool |
|---|---|---|---|
| Docker Compose / Codespaces / bare host | Service Principal with client_secret in AKV | client_secret in AKV, fetched at deploy time | Az PowerShell (`Set-HomelabCodespacesSp.ps1` for the Codespaces SP; `Create-HomelabOcAgentAzSp.ps1` for the `homelab-oc` instance; per-instance variants per substrate) |
| Kubernetes (per ADR 22) | UAMI Workload Identity per ServiceAccount | None — federated trust via OIDC | Az PowerShell (future UAMI bootstrap script) |

The pattern's invariants, regardless of substrate:

- **Per-workload identity** — never a shared identity across workloads. One SP (or UAMI) per workload, or per logical group if consolidation is justified.
- **Least-privilege RBAC** — the workload's role assignments cover only the operations it needs. Default-deny.
- **Source of truth lives in Azure, not the workload** — for SP: AKV holds the client_secret. For UAMI: the federated identity credential + role assignments live in Entra ID.
- **Consumer code uses `DefaultAzureCredential`** — substrate-agnostic. The Azure SDKs pick the right credential at runtime.
- **Identity is rotatable independently of the workload** — the workload does not own its identity; the platform owns it. Rotation does not require touching the workload's image or env.

---

## Implementation: Service Principal for non-cluster workloads

The original SP implementation details are preserved here for historical context and as the working pattern for the OpenCode on Cloudlab workload (#40). The same script pattern (Az PowerShell, no `az` CLI) extends to any future non-cluster workload.

### Identity and naming

- **SP display name:** `homelab-codespaces-sp` (project-and-purpose, not tool-specific, so future reuse doesn't require a rename). Per-instance OpenCode variants follow the `<project>-<substrate>-<role>-sp` pattern (e.g., `homelab-oc-agent-sp`, `prospera-oc-agent-sp`).
- **KV secret names:** `codespaces-sp-tenant-id`, `codespaces-sp-client-id`, `codespaces-sp-client-secret` — kebab-case, matching the existing `cloudlab-vps-key-priv` convention. Per-instance OpenCode variants use the `opencode-agent-sp-<instance-name>-{tenant-id,client-id,client-secret}` pattern (literal: prefix `opencode-agent-sp-` + instance name + the three suffixes). The same name layout will be used by the future UAMI bootstrap script (`Set-HomelabOpencodeUami.ps1` per #44), so consumer code is unchanged at cutover.
- **Container env var names:** `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` — fixed by the Azure Identity SDK's `EnvironmentCredential` contract.

### Scope and credentials

- **RBAC roles (per workload):**
  - `Contributor` on the workload's target resource group (control plane) — needed for the agent to create and modify Azure resources.
  - `Key Vault Secrets User` on `homelab-bysxdb-kv` (data plane) — separate from the control-plane role. Required so the workload can read project secrets the same way an interactive `Az` session does.
- **Credential type:** Client secret (password credential), not a certificate. The Microsoft Graph Bicep extension v1.0 GA does not expose the `addPassword` action as a Bicep resource (issue #38 closed as "Not planned"), so a Bicep-only path was rejected in favour of the simpler Az PowerShell route.
- **Default lifetime:** 365 days; rotated by re-running the same script.

### Bootstrap tool

- **Azure PowerShell only** — `New-AzADServicePrincipal` + `New-AzADSpCredential` + `New-AzRoleAssignment` (control plane on the RG + data plane on the KV) + `Set-AzKeyVaultSecret`. No Azure CLI (project rule: "Always use Az PowerShell — never Azure CLI"). No Microsoft Graph SDK install needed.
- Scripts: `scripts/Set-HomelabCodespacesSp.ps1` (Codespaces SP, the original pattern) and `scripts/Create-HomelabOcAgentAzSp.ps1` (per-instance for the `homelab-oc` OpenCode container, the live instance in flight). Same idempotent flow: check SP → create or rotate credential → assign RG `Contributor` + KV `Key Vault Secrets User` → write 3 secrets with `-Expires $endDate` → read back → print.

### MCP transport and runtime (for Azure MCP consumer workloads)

- **Transport:** local stdio (`type: "local"` in `opencode.json`). Credentials never leave the container; no Azure-hosted relay.
- **Runtime:** Node.js via `npx -y @azure/mcp@latest server start`.
- **Auth mechanism:** `DefaultAzureCredential` → `EnvironmentCredential` reading the three `AZURE_*` env vars.

---

## Implementation: UAMI Workload Identity (future, per ADR 22)

For Kubernetes-resident workloads on the homelab cluster, the SP path is replaced by UAMI Workload Identity per ServiceAccount. The full pattern is recorded in a future ADR; the high-level shape:

- One UAMI per K8s ServiceAccount.
- A federated identity credential on the UAMI establishes trust with the cluster's OIDC issuer and the specific ServiceAccount.
- The workload's pod has the ServiceAccount annotated with the UAMI's client ID.
- The Azure SDK's `WorkloadIdentityCredential` exchanges the pod's projected service-account token for an Entra token at runtime.
- No client_secret lives in the cluster. No AKV env-var plumbing. No manual rotation — the federated trust produces short-lived Entra tokens via the pod's projected service-account token, exchanged for an Entra access token at runtime.

The transition from SP (OpenCode on Cloudlab, in flight via #40) to UAMI (OpenCode on homelab k3s, future) is a one-way swap on the consumer side: `DefaultAzureCredential` already includes both credential types, so the workload's code does not change at cutover. Only the env-var-vs-WorkloadIdentityCredential source changes.

---

## Consequences

### Positive

- **Consistent identity model across substrates** — the pattern's invariants (per-workload, least-privilege, source-of-truth in Azure, rotatable independently) hold whether the workload runs on Compose or K8s. Only the identity type changes.
- **No workload uses a personal identity** — audit trail, blast-radius containment, and lifecycle independence are universal.
- **AKV remains the source of truth for SP credentials** — auditable, versioned (KV keeps previous secret values), and rotatable from one place via the same script that creates them.
- **UAMI per SA eliminates in-cluster secret plumbing** — once the cluster lands, the SP path's env-var-fetch ceremony is gone for cluster workloads.
- **Consumer code unchanged across substrate migrations** — `DefaultAzureCredential` handles both. A workload that works on Compose works on K8s without code changes.
- **The Codespaces emergency use case remains viable** — if a future Codespace is revived, the SP pattern re-applies via the same script (`Set-HomelabCodespacesSp.ps1`) with no new design work.

### Negative

- **Two identity types in flight during the transition** — SP for the OpenCode on Cloudlab workload (#40, in flight) and UAMI for the future homelab k8s workload. Operationally more complex during the cutover window; simplifies once all workloads are on the cluster.
- **SP credentials still require manual rotation** — the script must be re-run before the 365-day lifetime. UAMI per SA removes this concern for cluster workloads.
- **The UAMI pattern is more complex to set up** — federated identity credentials, OIDC issuer on the cluster, ServiceAccount annotations. The setup cost is higher; the operational benefits (no secrets in cluster, automatic rotation) outweigh it for cluster workloads.
- **The pattern's first execution (Codespaces SP) was never actually implemented** — `homelab-codespaces-sp` was never created because Codespaces became emergency-only. The pattern moved to OpenCode on Cloudlab via #40. The decision itself was sound; the specific use case simply never materialized.

---

## Alternatives Considered

- **HTTP/remote Azure MCP hosted on Azure Container Apps** — adds extra Azure infra (Container App + auth + monitoring), incurs network RTT on every tool call, and the SP credentials would have to be presented to a remote endpoint over the wire. Rejected as over-engineering for the evaluation scope.
- **Microsoft Graph Bicep extension for SP creation** — the extension is GA v1.0 (July 2025, Bicep v0.36.1+), but it cannot create a client secret in pure Bicep. A `deploymentScripts` wrapper around `Add-MgApplicationPassword` would work but adds ~3× the code of the Az PowerShell path. Rejected.
- **Reader-only RBAC on the target RG** — safer, but blocks evaluation's mutating-tool prompts. Rejected for the initial scope; can be tightened after evaluation completes.
- **Azure CLI for SP creation (`az ad sp create-for-rbac`)** — one-liner but violates the repo rule "Always use Az PowerShell — never Azure CLI". Rejected.
- **One SP per tool** (e.g., `homelab-opencode-sp`, `homelab-ansible-sp`) — would create credential-management overhead and force a rename the first time a second tool needed the identity. Rejected in favour of the project-scoped `homelab-codespaces-sp` for Codespaces and per-instance variants for the OpenCode workloads.
- **User-level Codespaces secret** — would scope the SP to a single developer account, not the repo. Rejected because the SP is a project asset, reusable by any contributor.
- **Long-lived UAMI credentials in a K8s Secret** — defeats the platform's secret-management primitives. Rejected; the federated identity credential pattern is the right K8s path.
- **Single shared identity across all agent workloads** — one SP (or one UAMI) for every agent. Simpler bootstrap but no per-workload audit, no per-workload blast-radius containment, no per-workload rotation. Rejected as a regression on the pattern's invariants.

---

## References

- ADR 04 — Hybrid Cloud Strategy
- ADR 10 — Ansible for Host Configuration Management
- ADR 17 — Adopt OpenCode for Agentic Homelab Development
- ADR 18 — Host OpenCode Server Instances on Homelab
- ADR 22 — Migrate Homelab Workloads to Kubernetes (k3s + Azure Arc on homelab) — the cluster-resident variant of this pattern
- Issue #16 — DR Simulation Agent Skill
- Issue #36 — Secret management via self-hosted Infisical (orthogonal to identity; can be revisited after UAMI lands)
- Issue #40 — Provision per-instance Azure service principals (in-flight execution of the SP path on Cloudlab)
- Future ADR — UAMI Workload Identity per ServiceAccount (to be authored; details the cluster-resident variant)
- Runbook 14 — GH Codespaces Service Principal for Homelab (bootstrap, verification, rotation, troubleshooting — note: the original SP for Codespaces was never created; the runbook documents the pattern, not a live deployment)
- [Microsoft docs — Workload Identity for Kubernetes](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Microsoft docs — Service principals](https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals)
