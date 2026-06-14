# Homelab Setup — Restic Backup (Azure Blob)

> Runbook for deploying Restic backup to Azure Blob Storage — no local disk required.

## Prerequisites

- [ ] SSH access via `ssh jarek@homelab`
- [ ] Server has `curl` and `bzip2`: `sudo apt install -y curl bzip2`
- [ ] Azure CLI installed on the server (see [2-docker.md](2-docker.md) for general server access)
- [ ] Azure subscription + `Az` PowerShell module installed on your local machine

---

## 1. Provision the Azure Storage Account and Container

Run from your laptop or a machine with the Az PowerShell module installed.

### 1.0 Set the correct subscription

```powershell
Connect-AzAccount -Subscription Cloud5-default
```

### 1.1 Create the storage account

The resource group `homelab-rg` already exists. Create the storage account inside it:

```powershell
New-AzStorageAccount -ResourceGroupName homelab-rg `
  -Name "homelabcloud5" `
  -Location polandcentral `
  -SkuName Standard_LRS `
  -Kind StorageV2 `
  -AccessTier Hot
```

Requirements met by this command:
- **Account kind**: StorageV2
- **Performance**: Standard (default)
- **Replication**: LRS
- **Tier**: Hot (general-purpose; no early-deletion penalty)

### 1.2 Create the `backups` container

```powershell
$ctx = (Get-AzStorageAccount -ResourceGroupName homelab-rg -Name "homelabcloud5").Context
New-AzStorageContainer -Name backups -Context $ctx -Permission Off
```

`-Permission Off` means private — no anonymous access.

### 1.3 Assign RBAC role to the Arc managed identity

The homelab server is enrolled in Azure Arc (see [6-azure-arc.md](6-azure-arc.md)), so it already has a system-assigned managed identity. Grant it access to the storage account:

```powershell
$connectedMachine = Get-AzConnectedMachine -ResourceGroupName homelab-rg -Name "homelab"
$sa = Get-AzStorageAccount -ResourceGroupName homelab-rg -Name "homelabcloud5"
New-AzRoleAssignment `
  -ObjectId $connectedMachine.IdentityPrincipalId `
  -RoleDefinitionName "Storage Blob Data Contributor" `
  -Scope $sa.Id
```

> **Storage Blob Data Contributor** allows Restic to read, write, and delete blobs — everything needed for backup, restore, check, and prune. The Arc agent handles token acquisition automatically — no keys, no secrets, no certificates to manage.

---

## 2. Install Restic (Official Binary)

> **Why not `apt`?** The Ubuntu package is compiled without the Azure Blob backend — see [this forum thread](https://forum.restic.net/t/version-0-16-4-and-azure-blob/7864/4). The official release from GitHub includes all backends.

SSH into the server and download the latest release:

```bash
ssh jarek@homelab

curl -LO https://github.com/restic/restic/releases/download/v0.18.1/restic_0.18.1_linux_amd64.bz2
bunzip2 restic_0.18.1_linux_amd64.bz2
chmod +x restic_0.18.1_linux_amd64
sudo mv restic_0.18.1_linux_amd64 /usr/local/bin/restic
```

Verify the correct binary is in use:

```bash
which restic
restic version
```

Expected: `/usr/local/bin/restic` and version `0.18.1`. See [Azure Blob Storage docs](https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html#microsoft-azure-blob-storage) for the backend reference.

---

## 3. Initialize the Repository

### 3.1 Log in with Azure CLI (managed identity)

```bash
az login --identity
```

Expected: logged in as `systemAssignedIdentity` with the Arc server's managed identity.

### 3.2 Create the Restic repo

```bash
AZURE_ACCOUNT_NAME=homelabcloud5 AZURE_FORCE_CLI_CREDENTIAL=true \
  restic -r azure:backups:/ init
```

You'll be prompted for a **repository password**. Choose a strong one and store it in your password manager — you'll need it for every restore.

### 3.3 Verify

```bash
AZURE_ACCOUNT_NAME=homelabcloud5 AZURE_FORCE_CLI_CREDENTIAL=true \
  restic -r azure:backups:/ snapshots
```

Expected output: `no snapshots found` (or an empty list).

---

## 4. Configure the Backup

Create a directory for config and a backup script for scheduled runs.

### 4.1 Create config file

```bash
sudo mkdir -p /etc/restic
```

Write the config:

```bash
sudo nano /etc/restic/env
```

Add:

```env
RESTIC_PASSWORD=your-strong-password
AZURE_ACCOUNT_NAME=homelabcloud5
AZURE_FORCE_CLI_CREDENTIAL=true
RESTIC_REPOSITORY=azure:backups:/
```

Then lock the file:

```bash
sudo chmod 600 /etc/restic/env
```

> Generate a strong password: `openssl rand -base64 32`. The `chmod 600` ensures only root can read the file.

### 4.2 Create the backup wrapper script

```bash
sudo nano /usr/local/bin/homelab-backup
```

Add:

```bash
#!/bin/bash
set -euo pipefail

set -a; source /etc/restic/env; set +a
restic backup \
  /opt/docker \
  /var/lib/docker/volumes \
  --exclude /var/lib/docker/volumes/portainer_data/* \
  --keep-daily=7 --keep-weekly=4 --keep-monthly=6
```

Then make it executable:

```bash
sudo chmod +x /usr/local/bin/homelab-backup
```

> `set -a` auto-exports sourced variables, making them available as env vars. **What's backed up**: `/opt/docker/` (compose files, configs) + all Docker volumes. Portainer's internal data is excluded.

---

## 5. Schedule Daily Backups (Systemd Timer)

### 5.1 Create the service unit

```bash
sudo nano /etc/systemd/system/restic-backup.service
```

```ini
[Unit]
Description=Restic backup — daily snapshot to Azure Blob

[Service]
Type=oneshot
ExecStart=/usr/local/bin/homelab-backup
User=root

[Install]
WantedBy=multi-user.target
```

### 5.2 Create the timer unit

```bash
sudo nano /etc/systemd/system/restic-backup.timer
```

```ini
[Unit]
Description=Daily Restic backup to Azure Blob
Requires=restic-backup.service

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

> `RandomizedDelaySec=1h` spreads the backup time to avoid predictable schedules. `Persistent=true` runs a missed backup immediately after boot.

### 5.3 Enable and start the timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable restic-backup.timer
sudo systemctl start restic-backup.timer
```

### 5.4 Verify

```bash
sudo systemctl status restic-backup.timer
sudo systemctl list-timers --all | grep restic
```

### 5.5 Run a manual backup

```bash
sudo systemctl start restic-backup.service
```

Check status and logs:

```bash
sudo systemctl status restic-backup.service
journalctl -u restic-backup.service
```

---

## 6. Test Restore Procedure

### 6.1 List snapshots

```bash
sudo bash -c 'set -a; source /etc/restic/env; set +a; restic snapshots'
```

### 6.2 Restore to a temporary directory

```bash
sudo mkdir -p /tmp/restic-restore
sudo bash -c 'set -a; source /etc/restic/env; set +a; restic restore latest --target /tmp/restic-restore'
```

### 6.3 Verify restored data

```bash
ls -la /tmp/restic-restore/
```

### 6.4 Clean up

```bash
sudo rm -rf /tmp/restic-restore
```

### 6.5 Check repository integrity

```bash
sudo bash -c 'set -a; source /etc/restic/env; set +a; restic check'
```

Run `check` quarterly to detect data corruption.

---

## 7. Maintenance

| Action | Frequency | Command |
|---|---|---|
| List snapshots | As needed | `sudo bash -c 'set -a; source /etc/restic/env; set +a; restic snapshots'` |
| Check repo integrity | Quarterly | `sudo bash -c 'set -a; source /etc/restic/env; set +a; restic check --read-data'` |
| Prune old snapshots | Auto (retention flags) | Restic keeps 7 daily, 4 weekly, 6 monthly |

> `--read-data` reads every pack file — it's I/O intensive and uses egress bandwidth. Run during low usage.

---

## 8. Cost Estimates (Azure Blob Hot — LRS)

| Data | Storage /mo | Egress (restore) |
|---|---|---|
| 10 GB | ~€0.20 | ~€0.05 |
| 50 GB | ~€1.00 | ~€0.25 |
| 200 GB | ~€4.00 | ~€1.00 |

Restic deduplication significantly reduces stored data for incremental backups — expect 30–50% of the raw source size.

---

## 9. Verification Checklist

- [ ] Azure storage account + container created
- [ ] Restic repo initialized: `sudo bash -c 'set -a; source /etc/restic/env; set +a; restic snapshots'`
- [ ] Config file locked: `sudo ls -la /etc/restic/env` (permissions `-rw-------`)
- [ ] Backup script executable: `sudo /usr/local/bin/homelab-backup`
- [ ] Systemd timer active: `sudo systemctl status restic-backup.timer`
- [ ] First backup completed: `journalctl -u restic-backup.service | tail`
- [ ] Restore procedure tested: files match source
- [ ] Repository integrity OK: `sudo bash -c 'set -a; source /etc/restic/env; set +a; restic check'`
