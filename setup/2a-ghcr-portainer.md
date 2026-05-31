# Homelab Setup — GHCR Registry in Portainer

> Runbook for adding the GitHub Container Registry (ghcr.io) as a registry in Portainer CE.

## Prerequisites

- [ ] Docker + Portainer CE running (see [2-docker.md](2-docker.md))
- [ ] Access to Portainer UI (via SSH tunnel: `http://localhost:9000`)
- [ ] GitHub account with access to the packages you want to pull

---

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

---

## 3. Verify It Works

### 3.1 Pull an image from GHCR

From the Portainer sidebar, go to **Images** → enter a GHCR image path:

```
ghcr.io/open-webui/open-webui:main
```

Click **Pull**. The image should download successfully (no `401 Unauthorized` or `denied` errors).

### 3.2 Verify in the registry list

Go back to **Settings** → **Registries**. `GHCR` should be listed with status **Connected**.

---

## 4. Using GHCR in Stacks / Compose Files

Once the registry is configured in Portainer, you can reference GHCR images directly in your `docker-compose.yml`:

```yaml
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    ports:
      - 127.0.0.1:3000:8080
    volumes:
      - ./open-webui-data:/app/backend/data
```

Portainer will use the stored GHCR credentials to pull the image automatically when you deploy the stack.

---

## 5. Token Rotation

GitHub PATs expire. When the token expires:

1. Generate a new PAT (classic) with the same scopes
2. In Portainer, go to **Settings** → **Registries** → click **GHCR**
3. Update the **Password** field with the new token
4. Click **Update registry**

> Portainer does not support fine-grained PATs for Docker registries — only classic tokens work.

---

## Checkpoint

- [ ] PAT (classic) created with `read:packages` scope
- [ ] GHCR registry added in Portainer with green "connected" status
- [ ] Successfully pulled an image from `ghcr.io` via Portainer UI
