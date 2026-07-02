# OpenCode Session Persistence + Backup in Codespaces

> Survive Dev Container rebuilds by symlinking OpenCode runtime data into
> the Codespaces persistent disk, and back up to Azure Blob Storage for
> off-Codespace protection.

## Overview

| | |
|---|---|
| **Trigger** | OpenCode sessions lost on every container rebuild; `/workspaces` destroyed on Codespace deletion |
| **Persistence** | Symlink `~/.local/{share,state}/opencode`, `~/.config/opencode`, `~/.cache/opencode` → `/workspaces/.opencode/*` |
| **Backup** | Tarball `/workspaces/.opencode` → `homelabcloud5/opencode-backups/` via Az PowerShell |
| **Restore** | `Get-AzStorageBlobContent` + `tar -xzf` + re-run symlink script (manual, documented below) |
| **Trigger points** | `postCreateCommand` for symlinks; manual invocation for backup |
| **Storage target** | Azure Blob, region `polandcentral`, container `homelabcloud5/opencode-backups` |
| **Auth** | Codespaces SP via env vars (`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`) |
| **Retention** | None — backups accumulate indefinitely |

## Why a sibling directory (not inside the repo)

OpenCode stores its runtime data in four locations under `$HOME`:

| Container path | Contents |
|---|---|
| `~/.local/share/opencode/` | `opencode.db` (SQLite, ~15 MB), WAL/SHM, `snapshot/`, `repos/`, `tool-output/`, `log/`, `auth.json` |
| `~/.local/state/opencode/` | `model.json`, `prompt-history.jsonl`, `session.json`, `locks/` |
| `~/.config/opencode/` | `opencode.jsonc`, `package.json`, `node_modules/` (MCP server installs) |
| `~/.cache/opencode/` | `models.json` (model registry), `bin/` (downloaded binaries) |

By default all four live on the container's ephemeral filesystem layer and are
wiped on every Dev Container rebuild. To survive rebuilds we move the data
to **`/workspaces/.opencode/`** — a sibling of the repo on the Codespaces
persistent disk — and replace the container paths with symlinks.

`/workspaces` is the only filesystem path Codespaces guarantees across
container rebuilds. Anything under it persists. Everything else is rebuilt
from the image on every container create.

Why a sibling of the repo (not `/workspaces/Homelab/.opencode`):

- **Outside the git work tree** — can never be committed by accident
- **Survives `git clean -fdx`** and repo renames / moves
- **Matches the existing `/workspaces/.codespaces` sibling pattern**
- **`/workspaces` is vscode-owned (UID 1000)** with `drwxrwx---` perms, so no permission issues for the container's `vscode` user

---

## Persistence

### Setup

- `.devcontainer/scripts/setup-opencode-persist.ps1` runs automatically on every container create via `postCreateCommand` (chained before the existing setup scripts in `.devcontainer/devcontainer.json:51`)
- On the **first** rebuild after this change, the script detects real directories at each container path, copies their contents into `/workspaces/.opencode/<name>/`, then replaces the container paths with symlinks
- On **subsequent** rebuilds the script detects the symlinks already in place and is a no-op

### Verification

After a rebuild (or after manually running the script):

```bash
# 1. Confirm the four symlinks point at /workspaces/.opencode
ls -la /home/vscode/.local/share/opencode \
       /home/vscode/.local/state/opencode \
       /home/vscode/.config/opencode \
       /home/vscode/.cache/opencode
# Expected: each line shows "-> /workspaces/.opencode/<name>"

# 2. Confirm data is at the new location
ls /workspaces/.opencode/share/
# Expected: opencode.db, opencode.db-shm, opencode.db-wal, snapshot/, repos/, ...

# 3. Confirm /workspaces/.opencode is OUTSIDE the repo (no false git noise)
git -C /workspaces/Homelab status --porcelain | grep -i opencode || echo "OK: no git noise"
```

### Test the durability claim

The verification steps above only confirm the *current* state is correct. To
prove the persistence actually survives a rebuild, perform this round-trip:

1. **Send a marker message.** In OpenCode, start a new session and send a
   recognizable prompt like `durability-test-marker-<timestamp>`. Note the
   session title and the time you sent it.
2. **Confirm the session is in the DB.**
   ```bash
   sqlite3 /workspaces/.opencode/share/opencode.db \
     "SELECT id, title, time_updated FROM session ORDER BY time_updated DESC LIMIT 3"
   # Expected: your marker session is at the top
   ```
3. **Trigger a rebuild.** In VS Code: `Dev Containers: Rebuild Container`
   (Command Palette → type "Rebuild Container" → select the Dev Containers
   command). This destroys the container and re-creates it from the image,
   re-running `postCreateCommand` (including `setup-opencode-persist.ps1`).
4. **Re-open OpenCode.** Look in the session picker for your marker session.
   It should be listed with the same title and timestamp.
5. **If the session is missing:**
   - Check `git -C /workspaces/Homelab log --oneline -5` to confirm the
     persistence commit landed in the branch you're rebuilding from
   - Verify `setup-opencode-persist.ps1` ran during `postCreateCommand`:
     look in the Codespaces creation log for `:: linked /home/vscode/.local/...`
   - Verify symlinks are in place (the standard verification steps above)
   - If symlinks exist but data is missing in `/workspaces/.opencode/`, the
     first-run migration may have failed; restore from the latest Azure Blob
     backup (see [Restore](#restore) below)

### Recovery

| Symptom | Fix |
|---|---|
| Symlink deleted | `pwsh -File .devcontainer/scripts/setup-opencode-persist.ps1` |
| `/workspaces/.opencode` wiped | Rebuild — OpenCode starts with fresh data, then back up from any blob restore |
| `opencode.db` corrupted | Restore from backup (see below) or delete `~/.local/share/opencode/` (it will be re-created as a fresh symlink on next run of the persistence script) |

---

## Backup

### Why back up?

`/workspaces` is durable across container rebuilds but **is destroyed when the Codespace itself is deleted** (manually, or automatically after the 30-day idle timeout). A blob backup gives a safety net for long-lived sessions worth preserving across Codespace deletion or a fresh `/workspaces` provisioning event.

### Prerequisite — one-time Azure setup

1. **Deploy `homelabcloud5` storage account** per [runbook 7](7-restic-backup.md) (issue #13). The OpenCode backup reuses the same storage account as the homelab-server restic backup; no new SA is created.
2. **Grant the Codespaces SP storage access** by running the dedicated role-grant script (separate from `Set-HomelabCodespacesSp.ps1` — see [runbook 14 § Additional role](14-gh-codespaces-sp-for-homelab.md#additional-role-storage-blob-data-contributor-added-2026-06-28-for-opencode-backups)):

   ```powershell
   pwsh -File scripts/Add-HomelabOpencodeBackupStorage.ps1 `
     -TenantId       <cloud5.ovh tenant ID> `
     -SubscriptionId <subscription ID>
   ```

   This creates the `opencode-backups` container on `homelabcloud5` and grants the Codespaces SP `Storage Blob Data Contributor` on the storage account. **Idempotent** — safe to re-run.

   The script **exits with an error** if `homelabcloud5` does not exist yet. Deploy the SA first per step 1.

### Run a backup

```bash
pwsh -File scripts/Backup-OpencodeData.ps1
```

The script:

1. Checks the three `AZURE_*` env vars are set (Codespaces secrets forward these at container create time)
2. Bails out cleanly if `/workspaces/.opencode` does not exist
3. Tarballs `/workspaces/.opencode` to `/tmp/opencode-<timestamp>.tar.gz` using `/usr/bin/tar` to preserve Unix mode bits (see "Why tar" note in the script header)
4. Authenticates the SP via `Connect-AzAccount -ServicePrincipal` and uploads the tarball to `homelabcloud5/opencode-backups/opencode-<timestamp>.tar.gz`
5. Removes the local tarball and prints the blob name + restore hint

### Inspect existing backups

```powershell
Connect-AzAccount -ServicePrincipal `
  -TenantId     $env:AZURE_TENANT_ID `
  -Credential (New-Object PSCredential($env:AZURE_CLIENT_ID, (ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force))) | Out-Null

Get-AzStorageBlob -Container opencode-backups `
  -Context (Get-AzStorageAccount -Name homelabcloud5 -ResourceGroupName homelab-rg).Context |
  Select-Object Name, Length, LastModified |
  Format-Table -AutoSize
```

---

## Restore

### From a backup blob

```powershell
# 1. Authenticate (if not already)
Connect-AzAccount -ServicePrincipal `
  -TenantId     $env:AZURE_TENANT_ID `
  -Credential (New-Object PSCredential($env:AZURE_CLIENT_ID, (ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force))) | Out-Null

# 2. List backups (pick the timestamp you want)
$ctx = (Get-AzStorageAccount -Name homelabcloud5 -ResourceGroupName homelab-rg).Context
Get-AzStorageBlob -Container opencode-backups -Context $ctx |
  Select-Object Name, Length, LastModified |
  Format-Table -AutoSize

# 3. Download the chosen tarball
Get-AzStorageBlobContent `
  -Container opencode-backups `
  -Blob 'opencode-20260628T120000Z.tar.gz' `
  -Context $ctx |
  Out-Null     # writes /tmp/opencode-<ts>.tar.gz and prints ContentLength

# 4. Extract over /workspaces
sudo tar -xzf /tmp/opencode-20260628T120000Z.tar.gz -C /workspaces/

# 5. Re-establish symlinks (in case extraction disturbed them)
pwsh -File .devcontainer/scripts/setup-opencode-persist.ps1
```

### Verify the restore

After the four steps above, open OpenCode — the restored session list should include whatever was captured in the backup tarball.

---

## Limitations

- **Single-Codespace scope for symlinks** — not cross-machine; `/workspaces` is local to one Codespace
- **Manual backup only** — no schedule, no auto-trigger; run `Backup-OpencodeData.ps1` when you want a snapshot
- **No retention policy** — backups accumulate in the container indefinitely (delete old blobs manually if storage cost becomes a concern; ~$0.02/GB/month at standard LRS rates)
- **Tied to `homelabcloud5` lifecycle** — if that storage account is deleted, all OpenCode backups are lost with it
- **Auth lifecycle** — relies on the Codespaces SP credentials; rotating the SP's secret (per runbook 14's `Set-HomelabCodespacesSp.ps1`) does not invalidate the storage role grant (RBAC role persists across SP credential rotations) but does require updating the Codespaces repo secret and rebuilding the Codespace for the new credential to flow through

---

## Files

| Path | Purpose |
|---|---|
| `.devcontainer/scripts/setup-opencode-persist.ps1` | Symlink the four OpenCode data dirs to `/workspaces/.opencode/*`; one-time migration + idempotent re-runs |
| `.devcontainer/scripts/setup-opencode.sh` | Idempotent install of the OpenCode CLI binary via the official installer; skips if `~/.opencode/bin/opencode` already exists, runs `curl -fsSL https://opencode.ai/install \| bash` otherwise, verifies the binary post-install |
| `.devcontainer/devcontainer.json` | `postCreateCommand` chains `setup-opencode-persist.ps1` then `setup-opencode.sh` then the existing setup scripts |
| `scripts/Backup-OpencodeData.ps1` | Manual backup to Azure Blob via Az PowerShell |
| `scripts/Add-HomelabOpencodeBackupStorage.ps1` | One-time deploy: creates `opencode-backups` container + grants SP role |

---

## References

- [Runbook 7: Restic backup to Azure Blob](7-restic-backup.md) — creates `homelabcloud5`
- [Runbook 14: Codespaces SP for Homelab](14-gh-codespaces-sp-for-homelab.md) — SP creation; the "Additional role" subsection documents the storage role grant
- [ADR 16: Codespaces SP for Homelab](../decisions/260628-16-gh-codespaces-sp-for-homelab.md)
- [Research 14: Backup cost comparison](../research/14-backup-cost-comparison.md)
