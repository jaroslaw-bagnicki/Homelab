# Azure Service Principal for OpenCode Instances

> One-time bootstrap + ongoing rotation: a Service Principal dedicated to the `homelab-oc` OpenCode instance, stored in `homelab-bysxdb-kv` Key Vault and injected by Ansible as container env vars (`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`). The Azure SDK + Azure MCP server read these via `DefaultAzureCredential` → `EnvironmentCredential`.

> **Note:** `example.com` is a placeholder domain used in this runbook for documentation purposes. Replace with the actual domain when following these steps for a real deployment.

## Overview

| | |
|---|---|
| **Trigger** | Per-instance Azure identity for non-interactive agent workloads (issue #40) — required so the `homelab-oc` container can call Azure APIs (Ansible, Bicep, Az cmdlets, Azure MCP) without inheriting the developer's personal identity |
| **SP display name** | `homelab-oc-agent-sp` |
| **RBAC role** | `Contributor` on `/subscriptions/a8a36bc1-79a7-49fe-9faa-92220103c66f/resourceGroups/homelab-rg` (control plane) + `Key Vault Secrets User` on `homelab-bysxdb-kv` (data plane) |
| **KV (source of truth)** | `homelab-bysxdb-kv` (RBAC-only, pre-existing) |
| **KV secret names** | `opencode-agent-sp-homelab-tenant-id`, `opencode-agent-sp-homelab-client-id`, `opencode-agent-sp-homelab-client-secret` |
| **Container env var names** | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` (Azure SDK contract — non-renameable) |
| **Credential type** | Client secret (password credential), not certificate |
| **Default lifetime** | 365 days (rotate via the same script) |
| **Long-term destination** | UAMI Workload Identity per K8s ServiceAccount when the homelab k3s cluster lands (issue #44) |

See [ADR 16](../decisions/16-agent-identity-pattern.md) for the design rationale. The Azure SDK `DefaultAzureCredential` chain already includes `WorkloadIdentityCredential` — consumer code is unchanged at cutover.

---

## Why a per-instance Service Principal

A developer's personal identity (interactive `Az` login, personal PAT) is the wrong identity for a non-interactive agent container, for three reasons (per [ADR 16](../decisions/16-agent-identity-pattern.md)):

1. **No audit trail for the workload** — actions are attributed to the person, not the workload, making it impossible to answer "what did `homelab-oc` do at 03:00 last night?"
2. **Inherits the developer's scope** — the workload gains whatever the developer has, which is broader than the workload needs.
3. **Tied to the developer's lifecycle** — if the developer rotates their session, the workload stops working.

A per-instance SP solves all three. The same pattern is extended to future workloads (one SP per non-interactive agent workload) — never one shared SP across multiple workloads.

---

## Prerequisites (your local machine)

The script `scripts/Create-HomelabOcAgentAzSp.ps1` uses the **Az PowerShell** module (project rule: `az` CLI is not used). You need the following RBAC roles on the tenant:

| Role | Scope | Why |
|---|---|---|
| `Application Administrator` (Entra) | Tenant | Create the app registration + SP |
| `User Access Administrator` | Subscription | Assign `Contributor` to the SP on `homelab-rg` |
| `Key Vault Secrets Officer` | `homelab-bysxdb-kv` | Write the 3 secrets to the vault |

If you own the subscription, all three are implicit (Owner inherits `User Access Administrator`, and Application Administrator is typically granted to subscription Owners via the Entra default). If `Set-AzKeyVaultSecret` returns `Forbidden`, grant the role with:

```powershell
New-AzRoleAssignment -SignInName (Get-AzContext).Account.Id `
  -RoleDefinitionName 'Key Vault Secrets Officer' `
  -Scope "/subscriptions/a8a36bc1-79a7-49fe-9faa-92220103c66f/resourceGroups/homelab-rg/providers/Microsoft.KeyVault/vaults/homelab-bysxdb-kv"
```

---

## One-time bootstrap

### Step 1 — Run the script on your local machine

From the repo root, in any PowerShell session with the `Az` module loaded:

```powershell
Connect-AzAccount -Tenant example.com -UseDeviceAuthentication
pwsh -File scripts/Create-HomelabOcAgentAzSp.ps1 `
  -TenantId       <example.com tenant ID> `
  -SubscriptionId a8a36bc1-79a7-49fe-9faa-92220103c66f
```

The script will:

1. Create `homelab-oc-agent-sp` (or rotate the credential if it already exists)
2. Assign `Contributor` on `homelab-rg` (idempotent, control plane)
3. Assign `Key Vault Secrets User` on `homelab-bysxdb-kv` (idempotent, data plane)
4. Write the 3 values to `homelab-bysxdb-kv` under `opencode-agent-sp-homelab-*` with `-Expires $endDate`
5. Read them back to verify
6. Print the 3 values for the runbook log

### Step 2 — Opt the instance in via Ansible inventory

Edit `ansible/host_vars/cloudlab.yml` and set `azure_sp: true` on the `homelab` entry:

```yaml
opencode_instances:
  - name: homelab
    azure_sp: true
  - name: prospera
  - name: test
```

Instances without `azure_sp: true` get no `AZURE_*` env vars — `EnvironmentCredential` is skipped at runtime.

### Step 3 — Re-run the workload playbook

The role fetches the 3 AKV secrets at deploy time and injects them as container env vars. The container restarts on env change.

```bash
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

Running the playbook on a fresh deploy is idempotent. Running it again with no template / image / KV change reports `changed=0`. The container restart is the only change.

---

## Verification

### Inside the container

```bash
docker exec opencode-homelab printenv | grep AZURE_
# Expect:
#   AZURE_CLIENT_ID=<the SP's appId>
#   AZURE_CLIENT_SECRET=<the SP's client_secret>
#   AZURE_TENANT_ID=<the tenant ID>
```

### Azure PowerShell login as the SP

```bash
docker exec -it opencode-homelab pwsh
PS> (Get-AzContext).Account
# Expect: Type=ServicePrincipal, Id=<the SP's appId>
PS> Get-AzRoleAssignment -ServicePrincipalName (Get-AzContext).Account.Id
# Expect: RoleDefinitionName=Contributor, Scope ends with /resourceGroups/homelab-rg
PS> Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudlab-vps-key-priv -AsPlainText | Select-Object -First 1
# Expect: a multi-line SSH private key, NOT a Forbidden error
```

### Azure MCP

In an Opencode session, ask:

> list the resource groups in my subscription using azure tools

Expected: a single resource group — `homelab-rg` — returned. If the prompt hangs or returns an auth error, see [Troubleshooting](#troubleshooting).

### Key Vault side

```powershell
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name opencode-agent-sp-homelab-client-secret -AsPlainText
# Expect: the same secret value the script printed
```

---

## Secret rotation

The SP credential has a default lifetime of 365 days. To rotate without breaking the running instance:

```powershell
pwsh -File scripts/Create-HomelabOcAgentAzSp.ps1 `
  -TenantId       <TID> `
  -SubscriptionId a8a36bc1-79a7-49fe-9faa-92220103c66f
```

The script:

- Detects the existing SP and rotates its password credential
- Overwrites the 3 AKV secrets (KV keeps previous versions — audit history is preserved)
- Prints the new `AZURE_CLIENT_SECRET` value

Then re-run the workload playbook to re-fetch and re-inject:

```bash
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

The container restarts on env change and the new credential is live. Set a calendar reminder ~30 days before the `$endDate` printed in the script output. Or re-run quarterly with `-SecretLifetimeDays 90`.

---

## What lives where

```
┌─────────────────────────────────────────────────────────────────┐
│  Your local machine (one-time + on rotation)                    │
│                                                                 │
│  pwsh -File scripts/Create-HomelabOcAgentAzSp.ps1               │
│      │                                                          │
│      ├─► Az.Resources cmdlets                                   │
│      │     • New-AzADServicePrincipal  (creates homelab-oc-     │
│      │       agent-sp + Contributor on homelab-rg)              │
│      │     • New-AzADSpCredential      (generates secret)       │
│      │                                                          │
│      └─► Az.KeyVault cmdlets                                    │
│            • Set-AzKeyVaultSecret × 3 → homelab-bysxdb-kv       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │  Ansible fetches at deploy time
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Ansible (run from dev container)                               │
│                                                                 │
│  opencode_instances: [{ name: homelab, azure_sp: true }]        │
│      │                                                          │
│      └─► docker_opencode_instances role                         │
│            • azure_rm_keyvaultsecret_info (idempotency check)   │
│            • azure_keyvault_secret × 3 (fetch tenant-id,        │
│              client-id, client-secret)                          │
│            • docker_container env: AZURE_TENANT_ID,             │
│              AZURE_CLIENT_ID, AZURE_CLIENT_SECRET               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │  Container env vars
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  opencode-homelab container (on cloudlab)                        │
│                                                                 │
│  $ printenv | grep AZURE_                                       │
│  AZURE_TENANT_ID=<...>                                          │
│  AZURE_CLIENT_ID=<...>                                          │
│  AZURE_CLIENT_SECRET=<...>                                      │
│                                                                 │
│  DefaultAzureCredential → EnvironmentCredential                 │
│  (Azure SDK, Azure MCP, Az cmdlets all read the env vars)       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Set-AzKeyVaultSecret: Operation returned an invalid status code 'Forbidden'` | Your account lacks `Key Vault Secrets Officer` on `homelab-bysxdb-kv` | Run the `New-AzRoleAssignment` one-liner from [Prerequisites](#prerequisites-your-local-machine) |
| `New-AzADServicePrincipal: Insufficient privileges to complete the operation` | You don't have Application Administrator in the tenant | Either grant it (Entra portal → Roles and administrators → Application Administrator → Add assignments) or have a tenant admin run the script |
| Playbook fails: `Azure SP credentials for 'homelab' not found in homelab-bysxdb-kv` | You ran the playbook before running the bootstrap script | Run `scripts/Create-HomelabOcAgentAzSp.ps1` first, then re-run the workload playbook |
| Playbook fails: `Key Vault secret 'opencode-agent-sp-homelab-tenant-id' not found` (HTTP 404 from the lookup) | AKV Secrets Officer role missing on the **Ansible controller identity**, not your local-machine identity | The Ansible controller is a separate identity — it needs `Key Vault Secrets User` (read) on the vault. The bootstrap script's local-machine `Secrets Officer` role is unrelated. |
| `(Get-AzContext).Account` inside the container is empty | Old container without AZURE_* env vars; restart didn't pick up the new inventory flag | Re-run the workload playbook; confirm `azure_sp: true` is on the homelab entry; check `docker inspect opencode-homelab \| jq '.[0].Config.Env' \| grep AZURE_` |
| Azure MCP tools succeed but `Get-AzContext` shows no account | You opened a new pwsh session after a container restart; the Az module's cached context is from before the restart | Run any `Az` cmdlet — `Connect-AzAccount` will fire and cache. Or `Disconnect-AzAccount; Connect-AzAccount -ServicePrincipal` to force a fresh SP login |
| SP can read `homelab-rg` but not other RGs | Working as designed — scope is intentionally limited to `homelab-rg` | If you need broader scope, update the role assignment in the script (the grant is idempotent — safe to re-run) |
| `Get-AzKeyVaultSecret` returns `Forbidden` inside the container | SP lacks `Key Vault Secrets User` data-plane role on the vault (control-plane `Contributor` does not grant data-plane access) | Re-run the bootstrap script — the `Key Vault Secrets User` assignment step is idempotent |
| `AADSTS700016: Application ... was not found` | Wrong `AZURE_CLIENT_ID` (typo, or pasted the `ObjectId` instead of the `AppId`) | Re-run the script, copy the exact `AZURE_CLIENT_ID` it prints (it's `appId`, not the GUID object ID) |

---

## Files touched by this runbook

| Path | What |
|---|---|
| `scripts/Create-HomelabOcAgentAzSp.ps1` | NEW — bootstrap + rotation script |
| `ansible/host_vars/cloudlab.yml` | EDIT — adds `azure_sp: true` to the homelab instance |
| `ansible/workloads/opencode/docker_opencode_instances/defaults/main.yml` | EDIT — adds 3 secret-name templates |
| `ansible/workloads/opencode/docker_opencode_instances/tasks/provision_instance.yml` | EDIT — adds optional SP credential fetch + env-var injection block |
| `ansible/workloads/opencode/README.md` | EDIT — §"Secrets" describes the optional SP credential flow |
| `docs/opencode-customization.md` | NEW — high-level index of the OpenCode customization workstream |
| `docs/runbooks/19-azure-sp-for-opencode.md` | NEW — this runbook |
| `docs/runbooks/README.md` | EDIT — adds row 19 to the runbook index |
| `docs/decisions/16-agent-identity-pattern.md` | EDIT — updates naming examples to the new `opencode-agent-sp-<instance-name>-*` pattern |

---

## Related

- [OpenCode customization index](../opencode-customization.md) — high-level view of the customization workstream
- [Workload README — OpenCode](../../ansible/workloads/opencode/README.md) — Ansible-side details
- [ADR 16 — Non-Interactive Agent Workload Identity Pattern](../decisions/16-agent-identity-pattern.md) — design rationale
- [ADR 18 — Host OpenCode Server Instances on Homelab](../decisions/18-opencode-sandbox.md) — AKV-as-source-of-truth (§9)
- [Runbook 17 — Deploy OpenCode on Cloudlab](17-deploy-opencode-on-cloudlab.md) — base deployment
- [Runbook 18 — Provision a New OpenCode Instance](18-provision-opencode-instance.md) — per-instance provisioning
- [Issue #40 — Provision per-instance Azure service principals](https://github.com/jaroslaw-bagnicki/Homelab/issues/40)
- [Issue #44 — Migrate Homelab workloads to Kubernetes (k3s + Arc on homelab)](https://github.com/jaroslaw-bagnicki/Homelab/issues/44) — long-term destination (UAMI per ServiceAccount replaces this SP)
