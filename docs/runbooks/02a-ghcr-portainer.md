# Homelab Setup — Container Registries in Portainer

> Runbooks for adding container registries to Portainer CE: GitHub Container Registry (`ghcr.io`) and the self-hosted Zot registry (`zot.cloud5.ovh`, issue #50).

## Prerequisites

- [ ] Docker + Portainer CE running (see [02-docker.md](02-docker.md))
- [ ] Access to Portainer UI (via SSH tunnel: `http://localhost:9000`)
- [ ] GitHub account with access to the packages you want to pull

---

# Part 1 — GHCR Registry in Portainer

## 1. Create a GitHub Personal Access Token (Classic)

Portainer authenticates to GHCR using a **GitHub username + PAT (classic)** — not a fine-grained token. The token only needs `read:packages` scope to pull public or private container images.

1. Go to GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. Click **Generate new token** → **Generate new token (classic)**
3. Fill in:
   - **Note**: `homelab-portainer-ghcr`
   - **Expiration**: 90 days (or custom — you'll need to rotate it)
   - **Scopes**: check `read:packages` (under the `write:packages` group)

   > If you also plan to **push** images to GHCR from this homelab, check `write:packages` and `delete:packages` instead.

4. Click **Generate token** and copy the token immediately — it won't be shown again.

---

## 2. Add GHCR as a Registry in Portainer

1. Open Portainer UI and navigate to **Settings** → **Registries**
2. Click **Add registry**
3. Select **Custom registry** as the provider (GHCR does not have a dedicated provider card)
4. Fill in the form:

   | Field | Value |
   |---|---|
   | **Name** | `GHCR` |
   | **Registry URL** | `ghcr.io` |
   | **Authentication** | ✅ Enable |

   | Field | Value |
   |---|---|
   | **Username** | Your GitHub username (e.g. `jaroslaw-bagnicki`) |
   | **Password** | The PAT (classic) from Step 1 |

5. Click **Add registry**

Portainer will test the credentials against `ghcr.io`. A green success message confirms the registry is reachable.

> **CE limitation**: The **Browse** button and registry access management are Portainer Business Edition features. In Community Edition (CE), you cannot browse registry contents from the UI, but you can still pull images by specifying the full image path (e.g. `ghcr.io/owner/image:tag`) — authentication and pulls work normally.

---

## 3. Verify It Works

### 3.1 Pull an image from GHCR

From the Portainer sidebar, go to **Images** → click **Pull image**:

1. Set **Registry** to `GHCR`
2. Enter the image path **without** the `ghcr.io/` prefix (Portainer prepends the registry URL automatically):

   ```
   jaroslaw-bagnicki/plutus-api:dev-1dc7962
   ```

The image should download successfully (no `401 Unauthorized` or `denied` errors).

### 3.2 Verify in the registry list

Go back to **Settings** → **Registries**. `GHCR` should be listed with the blue **authentication-enabled** badge.

---

## 4. Token Rotation

GitHub PATs expire. When the token expires:

1. Generate a new PAT (classic) with the same scopes
2. In Portainer, go to **Settings** → **Registries** → click **GHCR**
3. Update the **Password** field with the new token
4. Click **Update registry**

> Portainer does not support fine-grained PATs for Docker registries — only classic tokens work.

---

## Checkpoint — GHCR

- [ ] PAT (classic) created with `read:packages` scope
- [ ] GHCR registry added in Portainer with blue "authentication-enabled" badge
- [ ] Successfully pulled an image from `ghcr.io` via Portainer UI

---

# Part 2 — Zot Registry in Portainer

> Adds the self-hosted Zot registry (`zot.cloud5.ovh`, issue #50) to Portainer CE. The Zot workload is deployed per [20-deploy-zot.md](20-deploy-zot.md).

## Prerequisites

- [ ] Zot workload deployed and reachable: `curl -u zot-admin:$PASSWORD https://zot.cloud5.ovh/v2/_catalog` returns the catalog (see [20-deploy-zot.md](20-deploy-zot.md))
- [ ] Portainer CE running and accessible (see [02-docker.md](02-docker.md))

## 1. Retrieve the Zot credentials

The registry credentials live in `homelab-bysxdb-kv`:

```powershell
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name zot-registry-user -AsPlainText
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name zot-registry-password -AsPlainText
```

The user is `zot-admin` (the registry's global admin via `adminPolicy`). The registry requires this credential for **both** push and pull — there is no anonymous access.

## 2. Add Zot as a Registry in Portainer

1. Open Portainer UI and navigate to **Settings** → **Registries**
2. Click **Add registry**
3. Select **Custom registry** as the provider
4. Fill in the form:

   | Field | Value |
   |---|---|
   | **Name** | `Zot` |
   | **Registry URL** | `zot.cloud5.ovh` |
   | **Authentication** | ✅ Enable |

   | Field | Value |
   |---|---|
   | **Username** | `zot-admin` (from AKV `zot-registry-user`) |
   | **Password** | AKV `zot-registry-password` |

5. Click **Add registry**

Portainer tests the credentials against `zot.cloud5.ovh`. A green success message confirms the registry is reachable.

> **CE limitation**: same as GHCR — no **Browse** button in Community Edition; pull by full image path works normally.

## 3. Verify It Works

### 3.1 Pull an image from Zot

From the Portainer sidebar, go to **Images** → click **Pull image**:

1. Set **Registry** to `Zot`
2. Enter the image path **without** the `zot.cloud5.ovh/` prefix (Portainer prepends the registry URL automatically):

   ```
   opencode/oc-homelab:1.0.0
   ```

The image should download successfully (no `401 Unauthorized` or `authorization failed` errors).

### 3.2 Verify in the registry list

Go back to **Settings** → **Registries**. `Zot` should be listed with the blue **authentication-enabled** badge.

## 4. Credential Rotation

When the Zot password is rotated (see [20-deploy-zot.md](20-deploy-zot.md) §1):

1. Re-run `New-HomelabZotRegistryCredential.ps1 -Force` and re-run the Zot playbook
2. In Portainer, go to **Settings** → **Registries** → click **Zot**
3. Update the **Password** field with the new AKV value
4. Click **Update registry**

## Checkpoint — Zot

- [ ] Zot registry added in Portainer with blue "authentication-enabled" badge
- [ ] Successfully pulled `zot.cloud5.ovh/opencode/oc-homelab:1.0.0` via Portainer UI
