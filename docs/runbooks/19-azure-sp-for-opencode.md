# Azure Service Principal for OpenCode Instances

> One-time bootstrap + ongoing rotation: a Service Principal dedicated to the `homelab-oc` OpenCode instance, stored in `homelab-bysxdb-kv` Key Vault and injected by Ansible as container env vars (`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`). The Azure SDK + Azure MCP server read these via `DefaultAzureCredential` → `EnvironmentCredential`.

> **Note:** `example.com` is a placeholder domain used in this runbook for documentation purposes. Replace with the actual domain when following these steps for a real deployment.

## Overview

| | |
|---|---|
| **Trigger** | Per-instance Azure identity for non-interactive agent workloads (issue #40) |
| **SP display name** | `homelab-oc-agent-sp` |
| **RBAC role** | `Contributor` on `homelab-rg` (control plane) + `Key Vault Secrets User` on `homelab-bysxdb-kv` (data plane) |
| **KV (source of truth)** | `homelab-bysxdb-kv` (RBAC-only, pre-existing) |
| **KV secret names** | `opencode-homelab-sp-tenant-id`, `opencode-homelab-sp-client-id`, `opencode-homelab-sp-client-secret` |
| **Container env var names** | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` (Azure SDK contract — non-renameable) |
| **Credential type** | Client secret (password credential) |
| **Default lifetime** | 90 days (rotate via `Rotate-HomelabOcAgentAzSp.ps1`) |
| **Long-term destination** | UAMI Workload Identity per K8s ServiceAccount (issue #44) |

See [ADR 16](../decisions/16-agent-identity-pattern.md) for design rationale. The `DefaultAzureCredential` chain already includes `WorkloadIdentityCredential` — consumer code is unchanged at cutover.

---

## Prerequisites

Run this runbook from an **interactive user session** on your local machine, signed into Az PowerShell. You need:

- **Azure RBAC:** `Owner` on the target subscription.
- **Entra ID role:** `Application Administrator` or `Cloud Application Administrator`.
- **PowerShell 7** with the `Az` module loaded.

---

## One-time bootstrap

### Step 1 — Run the script

From the repo root, in a PowerShell session with the `Az` module loaded:

```powershell
Connect-AzAccount -UseDeviceAuthentication
scripts/Create-HomelabOcAgentAzSp.ps1
```

The script is parameterless — it reads the tenant and subscription from the current `Az` context. It:

1. Checks whether `homelab-oc-agent-sp` already exists. If so, exits cleanly.
2. Validates that `homelab-rg` and `homelab-bysxdb-kv` exist in the current subscription.
3. Creates the SP and auto-grants `Contributor` on `homelab-rg`.
4. Writes the 3 values to `homelab-bysxdb-kv` under `opencode-homelab-sp-*` with `-Expires $endDate`.
5. Grants `Key Vault Secrets User` on `homelab-bysxdb-kv` to the new SP.
6. Prints confirmation (no secret values are logged).

### Step 2 — Opt the instance in via Ansible inventory

Edit `ansible/host_vars/cloudlab.yml` and set `azure_sp: true` on the `homelab` entry:

```yaml
opencode_instances:
  - name: homelab
    azure_sp: true
  - name: prospera
  - name: test
```

### Step 3 — Authenticate Azure CLI for Ansible

Ansible's `azure.azcollection` modules authenticate via the Azure CLI token cache, which is separate from the Az PowerShell cache. You must run `az login` even if you already logged in with `Connect-AzAccount`.

```bash
az login --use-device-code
```

> You cannot reuse the Az PowerShell token for Azure CLI.

### Step 4 — Validate pre-requisites

Run the pre-flight check to confirm Azure CLI auth, Python package compatibility, and SSH connectivity are all healthy:

```bash
scripts/Validate-PlaybookPrereqs.ps1
```

Fix any `FAIL` items before continuing.

### Step 5 — Re-run the workload playbook

The role fetches the 3 AKV secrets at deploy time and injects them as container env vars. The container restarts on env change.

```bash
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

Re-running the playbook with no template / image / KV change reports `changed=0`. The container restart is the only change.

---

## Verification

### Inside the container

```bash
docker exec opencode-homelab printenv | grep AZURE_
```

### Azure PowerShell login as the SP

The `ghcr.io/anomalyco/opencode:latest` image does not include PowerShell. If you need to verify the SP from inside the container, use the Azure SDK credential chain instead. Alternatively, verify from the host or Codespace:

```powershell
Get-AzRoleAssignment -ServicePrincipalName <SP-appId>
# Expect: RoleDefinitionName=Contributor, Scope ends with /resourceGroups/homelab-rg
```

### Azure MCP

In an Opencode session, ask:

> list the resource groups in my subscription using azure tools

Expected: a single resource group — `homelab-rg` — returned.

---

## Rotate

When the credential approaches its 90-day expiry, run the rotation script. The SP object ID is preserved; only the client_secret rotates.

```powershell
scripts/Rotate-HomelabOcAgentAzSp.ps1
az login --use-device-code
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

The script:
- Looks up the SP by display name; fails if it doesn't exist.
- Generates a new credential with 90-day expiry.
- Updates `opencode-homelab-sp-client-secret` in `homelab-bysxdb-kv`.
- Prints confirmation (no secret values logged).

---

## Files touched by this runbook

| Path | What |
|---|---|
| `scripts/Create-HomelabOcAgentAzSp.ps1` | NEW — bootstrap script |
| `scripts/Rotate-HomelabOcAgentAzSp.ps1` | NEW — credential rotation script |
| `scripts/Validate-PlaybookPrereqs.ps1` | NEW — pre-flight validation |
| `ansible/host_vars/cloudlab.yml` | EDIT — adds `azure_sp: true` to the homelab instance |
| `ansible/workloads/opencode/docker_opencode_instances/defaults/main.yml` | EDIT — 3 secret-name templates |
| `ansible/workloads/opencode/docker_opencode_instances/tasks/provision_instance.yml` | EDIT — optional SP credential fetch + env-var injection |
| `ansible/workloads/opencode/README.md` | EDIT — §Secrets describes the optional SP flow |
| `docs/opencode-customization.md` | NEW — index of the OpenCode customization workstream |
| `docs/runbooks/19-azure-sp-for-opencode.md` | NEW — this runbook |
| `docs/runbooks/README.md` | EDIT — adds row 19 |
| `docs/decisions/16-agent-identity-pattern.md` | EDIT — naming + rotation policy |

---

## References

- [ADR 16](../decisions/16-agent-identity-pattern.md) — design rationale
- [ADR 18](../decisions/18-opencode-sandbox.md) — AKV-as-source-of-truth
- [Runbook 17](17-deploy-opencode-on-cloudlab.md) — base deployment
- [Runbook 18](18-provision-opencode-instance.md) — per-instance provisioning
- [Workload README — OpenCode](../../ansible/workloads/opencode/README.md) — Ansible-side details
- [OpenCode customization index](../opencode-customization.md) — workstream overview
