# GH Codespaces Service Principal for Homelab

> One-time bootstrap + ongoing rotation: a Service Principal dedicated to the
> Homelab project's GitHub Codespaces sessions, stored in the existing
> `homelab-bysxdb-kv` Key Vault and exposed to the dev container via
> repository-level Codespaces secrets.

## Overview

| | |
|---|---|
| **Trigger** | Opencode evaluation (MCP server), but the SP is a **Homelab project asset**, not tool-specific — reusable by any Codespace workload touching `homelab-rg` |
| **SP display name** | `homelab-codespaces-sp` |
| **RBAC role** | `Contributor` on `/subscriptions/a8a36bc1-79a7-49fe-9faa-92220103c66f/resourceGroups/homelab-rg` (control plane) + `Key Vault Secrets User` on `homelab-bysxdb-kv` (data plane) |
| **KV (source of truth)** | `homelab-bysxdb-kv` (RBAC-only, pre-existing) |
| **KV secret names** | `codespaces-sp-tenant-id`, `codespaces-sp-client-id`, `codespaces-sp-client-secret` |
| **Codespaces secret names** | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` (Azure SDK contract — non-renameable) |
| **Codespaces secret scope** | Repository-level |
| **Credential type** | Client secret (password credential), not certificate |
| **Default lifetime** | 365 days (rotate via the same script) |

See [ADR 16](../decisions/260628-16-gh-codespaces-sp-for-homelab.md) for the design rationale.

---

## Why a Service Principal (and not device-auth)

Codespaces sessions are **ephemeral** — you don't get a stable, interactive browser
for `Connect-AzAccount -UseDeviceAuthentication` to land on. A Service Principal
gives the container a non-interactive identity that can be:

- Injected via env vars at container start (Codespaces secret → env var → process)
- Reused by **multiple tools** running inside the same Codespace (Opencode MCP,
  Ansible playbooks touching Azure, future MCP servers, ad-hoc `Az` cmdlets)
- Stored in the existing Key Vault so the secret is auditable, versioned, and
  rotatable from one place

---

## Prerequisites (your local machine)

The script `scripts/Set-HomelabCodespacesSp.ps1` uses the **Az PowerShell** module
(repo rule: `az` CLI is not used in this project). You need the following RBAC
roles on the **cloud5.ovh** tenant:

| Role | Scope | Why |
|---|---|---|
| `Application Administrator` (Entra) | Tenant | Create the app registration + SP |
| `User Access Administrator` | Subscription | Assign `Contributor` to the SP on `homelab-rg` |
| `Key Vault Secrets Officer` | `homelab-bysxdb-kv` | Write the 3 secrets to the vault |

If you own the subscription, all three are implicit (Owner inherits
`User Access Administrator`, and Application Administrator is typically granted
to subscription Owners via the Entra default). If `Set-AzKeyVaultSecret`
returns `Forbidden`, grant the role with:

```powershell
New-AzRoleAssignment -ObjectId (Get-AzContext).Account.Id \
  -RoleDefinitionName 'Key Vault Secrets Officer' \
  -Scope "/subscriptions/a8a36bc1-79a7-49fe-9faa-92220103c66f/resourceGroups/homelab-rg/providers/Microsoft.KeyVault/vaults/homelab-bysxdb-kv"
```

---

## One-time bootstrap

### Step 1 — Run the script on your local machine

From the repo root, in any PowerShell session with the `Az` module loaded:

```powershell
Connect-AzAccount -Tenant cloud5.ovh -UseDeviceAuthentication
pwsh -File scripts/Set-HomelabCodespacesSp.ps1 `
  -TenantId       <cloud5.ovh tenant ID> `
  -SubscriptionId a8a36bc1-79a7-49fe-9faa-92220103c66f
```

The script will:

1. Create `homelab-codespaces-sp` (or rotate the credential if it already exists)
2. Assign `Contributor` on `homelab-rg` (idempotent, control-plane)
3. Assign `Key Vault Secrets User` on `homelab-bysxdb-kv` (idempotent, data-plane)
4. Write the 3 values to `homelab-bysxdb-kv` under `codespaces-sp-*`
5. Read them back to verify
6. Print the 3 values for you to paste into GitHub

### Step 2 — Add the 3 values to GitHub Codespaces secrets

Repository-level secrets (any user with write access on the repo can use them —
matches the single-developer evaluation scope):

1. Open <https://github.com/jaroslaw-bagnicki/Homelab/settings/secrets/codespaces>
2. Click **New repository secret** three times:

   | Name | Value (paste from script output) |
   |---|---|
   | `AZURE_TENANT_ID` | the `cloud5.ovh` tenant ID |
   | `AZURE_CLIENT_ID` | the SP's `appId` |
   | `AZURE_CLIENT_SECRET` | the password credential `SecretText` |

3. Verify all three are listed under the **Codespaces** tab (not Actions / Dependabot)

### Step 3 — Open a fresh Codespace

Open a **new** Codespace on `main` (do not just resume — Codespaces secrets only
populate the env at container-creation time). The boot sequence will:

1. Install Node.js via the `devcontainer` Node feature (needed for `npx`)
2. Run `.devcontainer/scripts/setup-azure-mcp-prereqs.sh` — writes a
   masked summary of the 3 env vars + npx version to `/tmp/install-azmcp.log`
3. Run `setup-profile.ps1` — `Connect-AzAccount -ServicePrincipal` using the 3
   env vars, so interactive `Az` cmdlets also run as the SP
4. Opencode launches → reads `opencode.json` → spawns
   `npx -y @azure/mcp@latest server start` with the 3 env vars passed through
   → the Azure MCP server authenticates via `DefaultAzureCredential` →
   `EnvironmentCredential`

---

## Verification

### Codespace boot

```bash
tail -f /tmp/install-azmcp.log
# Expect three masked values + "npx version: <semver>"
```

### PowerShell login (SP)

```powershell
pwsh
PS> (Get-AzContext).Account
# Expect: Type=ServicePrincipal, Id=<the SP's appId>
PS> Get-AzRoleAssignment -ObjectId (Get-AzContext).Account.Id.Replace('-','')
# Expect: RoleDefinitionName=Contributor, Scope ends with /resourceGroups/homelab-rg
PS> Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudlab-vps-key-priv -AsPlainText | Select-Object -First 1
# Expect: a multi-line SSH private key, NOT a Forbidden error
```

### Opencode + Azure MCP

In an Opencode session, ask:

> list the resource groups in my subscription using azure tools

Expected: a single resource group — `homelab-rg` — returned, with the
`homelab-rg/...` location etc. If the prompt hangs or returns an auth error,
see [Troubleshooting](#troubleshooting) below.

### Key Vault side

```powershell
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name codespaces-sp-client-secret -AsPlainText
# Expect: the same secret value you pasted into Codespaces
```

---

## Secret rotation

The SP credential has a default lifetime of 365 days. To rotate without
breaking the existing Codespace:

```powershell
pwsh -File scripts/Set-HomelabCodespacesSp.ps1 `
  -TenantId       <TID> `
  -SubscriptionId a8a36bc1-79a7-49fe-9faa-92220103c66f
```

The script:

- Detects the existing SP and rotates its password credential
- Overwrites the 3 KV secrets (KV keeps previous versions — you can audit
  history in the portal)
- Prints the new `AZURE_CLIENT_SECRET` value

Then in GitHub:

1. Update the `AZURE_CLIENT_SECRET` repository secret with the new value
2. Existing Codespaces need to be **rebuilt** (not just restarted) to pick up
   the new env var — `Dev Containers: Rebuild Container` from the command palette
3. Alternatively, open a new Codespace

Set a calendar reminder ~30 days before the `$endDate` printed in the script
output. Or re-run quarterly with `-SecretLifetimeDays 90`.

---

## What lives where

```
┌─────────────────────────────────────────────────────────────────┐
│  Your local machine (one-time + on rotation)                    │
│                                                                 │
│  pwsh -File scripts/Set-HomelabCodespacesSp.ps1                 │
│      │                                                          │
│      ├─► Az.Resources cmdlets                                   │
│      │     • New-AzADServicePrincipal  (creates homelab-        │
│      │       codespaces-sp + Contributor on homelab-rg)         │
│      │     • New-AzADSpCredential      (generates secret)       │
│      │                                                          │
│      └─► Az.KeyVault cmdlets                                    │
│            • Set-AzKeyVaultSecret × 3 → homelab-bysxdb-kv       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │  you paste the 3 values
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  GitHub: jaroslaw-bagnicki/Homelab                              │
│  Settings → Secrets and variables → Codespaces                  │
│                                                                 │
│  Repository secrets: AZURE_TENANT_ID, AZURE_CLIENT_ID,          │
│                      AZURE_CLIENT_SECRET                        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │  Codespaces injects as env vars
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Dev container (Codespace)                                      │
│                                                                 │
│  /tmp/install-azmcp.log        ← prereq-check summary           │
│                                                                 │
│  profile.ps1                   ← Connect-AzAccount -            │
│                                  ServicePrincipal using env vars│
│                                                                 │
│  opencode.json → mcp.azure     ← npx -y @azure/mcp@latest       │
│                                  server start                   │
│                                  (EnvironmentCredential reads   │
│                                   AZURE_* env vars)             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Set-AzKeyVaultSecret: Operation returned an invalid status code 'Forbidden'` | Your account lacks `Key Vault Secrets Officer` on `homelab-bysxdb-kv` | Run the `New-AzRoleAssignment` one-liner from [Prerequisites](#prerequisites) |
| `New-AzADServicePrincipal: Insufficient privileges to complete the operation` | You don't have Application Administrator in the tenant | Either grant it (Entra portal → Roles and administrators → Application Administrator → Add assignments) or have a tenant admin run the script |
| Opencode shows "Azure MCP: connection refused" | Env vars missing in the Codespace | Check `/tmp/install-azmcp.log` — if the env vars show `<unset>`, the Codespaces secrets weren't created at the repo level or the Codespace was resumed (not rebuilt) |
| `npx: command not found` when Opencode tries to start the Azure MCP | Node feature didn't install | Rebuild container. Verify `devcontainer.json` has `"ghcr.io/devcontainers/features/node:2": {}` in the `features` block |
| `npx -y @azure/mcp@latest server start` runs but every tool call returns `AADSTS700016: Application ... was not found` | Wrong `AZURE_CLIENT_ID` (typo, or pasted the `ObjectId` instead of the `AppId`) | Re-run the script, copy the exact `AZURE_CLIENT_ID` it prints (it's `appId`, not the GUID object ID) |
| Azure MCP tools succeed but `Get-AzContext` shows no account | You opened a new pwsh session after a Codespace restart; the profile ran but context isn't cached | Run any `Az` cmdlet — `Connect-AzAccount` will fire and cache. Or `Disconnect-AzAccount; . $PROFILE` to force a re-run |
| SP can read `homelab-rg` but not other RGs | Working as designed — scope is intentionally limited to `homelab-rg` | If you need broader scope, update the `-RoleAssignment` step in the script (re-run with no other changes; the role assignment is idempotent) |
| `Get-AzKeyVaultSecret` returns `Forbidden` inside the Codespace | SP lacks `Key Vault Secrets User` data-plane role on the vault (control-plane `Contributor` does not grant data-plane access) | Re-run the bootstrap script — the `Key Vault Secrets User` assignment step is idempotent |
| Forgot to paste one of the 3 values | Partial Codespaces secret config | Add the missing secret, then rebuild the Codespace |

---

## Files touched by this runbook

| Path | What |
|---|---|
| `scripts/Set-HomelabCodespacesSp.ps1` | NEW — bootstrap + rotation script |
| `opencode.json` | adds `azure` MCP entry (local stdio, env-driven) |
| `.devcontainer/devcontainer.json` | adds Node feature, adds prereq-check to `postCreateCommand` |
| `.devcontainer/scripts/setup-azure-mcp-prereqs.sh` | NEW — masked env-var check + npx availability |
| `.devcontainer/config/profile.ps1` | SP-aware `Connect-AzAccount` (falls back to device-auth) |
| `docs/decisions/260628-16-gh-codespaces-sp-for-homelab.md` | NEW — design rationale |
