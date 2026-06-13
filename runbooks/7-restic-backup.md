# Homelab Setup — Restic Backup (Azure Blob)

> Runbook for deploying Restic backup to Azure Blob Storage — no local disk required.

## Prerequisites

- [ ] Docker Engine + Compose running (see [2-docker.md](2-docker.md))
- [ ] SSH access via `ssh jarek@homelab.local`
- [ ] Azure subscription (any region) + `Az` PowerShell module installed on your local machine

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

## 2. Initialize the Restic Repository on Azure Blob

On the homelab server, run the Restic container with managed identity authentication:

```bash
ssh jarek@homelab.local
sudo docker run --rm \
  -e AZURE_STORAGE_ACCOUNT=homelabcloud5 \
  -e AZURE_USE_MANAGED_IDENTITY_CREDENTIAL=true \
  restic/restic:latest \
  init --repo azure:backups:/homelab
```

You'll be prompted for a **repository password**. Choose a strong one and store it in your password manager — you'll need it for every restore.

> **Security note**: The `RESTIC_PASSWORD` is the only secret. Azure auth is handled by the Arc managed identity — no keys, no certs.

### Verify

```bash
sudo docker run --rm \
  -e AZURE_STORAGE_ACCOUNT=homelabcloud5 \
  -e AZURE_USE_MANAGED_IDENTITY_CREDENTIAL=true \
  restic/restic:latest \
  snapshots --repo azure:backups:/homelab
```

Enter the password. Expected output: `no snapshots found` (or an empty list).

---

## 3. Add Restic to Docker Compose

All commands run from `/opt/docker/`.

### 3.1 Create a `.env` file with credentials

```bash
nano /opt/docker/.env
```

Add:

```env
RESTIC_PASSWORD=your-strong-password
AZURE_STORAGE_ACCOUNT=homelabcloud5
AZURE_USE_MANAGED_IDENTITY_CREDENTIAL=true
```

> Generate a strong password: `openssl rand -base64 32`. The Arc managed identity handles Azure auth — no keys, no secrets, no certs to store.

### 3.2 Add the Restic service

```bash
nano docker-compose.yml
```

Append under `services:`:

```yaml
  restic:
    image: restic/restic:latest
    container_name: restic
    profiles:
      - backup
    env_file:
      - .env
    environment:
      - AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT}
      - AZURE_USE_MANAGED_IDENTITY_CREDENTIAL=${AZURE_USE_MANAGED_IDENTITY_CREDENTIAL}
    volumes:
      - /opt/docker:/data/homelab-config:ro
      - /var/lib/docker/volumes:/data/docker-volumes:ro
    command: >
      backup /data
      --repo azure:backups:/homelab
      --keep-daily=7 --keep-weekly=4 --keep-monthly=6
      --exclude /data/docker-volumes/portainer_data/*
```

> **What's backed up**: The entire `/opt/docker/` directory (compose files, Caddyfile, configs) and all Docker volumes (service data, databases). The Portainer volume is excluded since Portainer manages its own snapshots.

### 3.3 Verify the Compose config

```bash
docker compose config
```

No errors expected.

---

## 4. Schedule Daily Backups (Systemd Timer)

Use a systemd timer to run `restic` every day.

### 4.1 Create the service unit

```bash
sudo nano /etc/systemd/system/restic-backup.service
```

```ini
[Unit]
Description=Restic backup — daily snapshot to Azure Blob
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/docker
ExecStart=/usr/bin/docker compose run --rm restic
User=jarek
Group=docker

[Install]
WantedBy=multi-user.target
```

### 4.2 Create the timer unit

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

### 4.3 Enable and start the timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable restic-backup.timer
sudo systemctl start restic-backup.timer
```

### 4.4 Verify

```bash
sudo systemctl status restic-backup.timer
sudo systemctl list-timers --all | grep restic
```

### 4.5 Run a manual backup

```bash
sudo systemctl start restic-backup.service
```

Check status and logs:

```bash
sudo systemctl status restic-backup.service
journalctl -u restic-backup.service
```

---

## 5. Test Restore Procedure

### 5.1 List snapshots

```bash
sudo docker run --rm \
  --env-file /opt/docker/.env \
  restic/restic:latest \
  snapshots --repo azure:backups:/homelab
```

### 5.2 Restore to a temporary directory

```bash
sudo docker run --rm \
  -v /tmp/restic-restore:/restore \
  --env-file /opt/docker/.env \
  restic/restic:latest \
  restore latest --target /restore --repo azure:backups:/homelab
```

### 5.3 Verify restored data

```bash
ls -la /tmp/restic-restore/
```

### 5.4 Clean up

```bash
sudo rm -rf /tmp/restic-restore
```

### 5.5 Check repository integrity

```bash
sudo docker run --rm \
  --env-file /opt/docker/.env \
  restic/restic:latest \
  check --repo azure:backups:/homelab
```

Run `check` quarterly to detect data corruption.

---

## 6. Maintenance

| Action | Frequency | Command |
|---|---|---|
| List snapshots | As needed | `sudo docker run --rm --env-file /opt/docker/.env restic/restic:latest snapshots --repo azure:backups:/homelab` |
| Check repo integrity | Quarterly | `sudo docker run --rm --env-file /opt/docker/.env restic/restic:latest check --repo azure:backups:/homelab --read-data` |
| Prune old snapshots | Auto (retention flags in command) | Restic keeps 7 daily, 4 weekly, 6 monthly |

> `--read-data` reads every pack file — it's I/O intensive and uses egress bandwidth. Run during low usage.

---

## 7. Cost Estimates (Azure Blob Hot — LRS)

| Data | Storage /mo | Egress (restore) |
|---|---|---|
| 10 GB | ~€0.20 | ~€0.05 |
| 50 GB | ~€1.00 | ~€0.25 |
| 200 GB | ~€4.00 | ~€1.00 |

Restic deduplication significantly reduces stored data for incremental backups — expect 30–50% of the raw source size.

---

## Verification Checklist

- [ ] Azure storage account + container created
- [ ] Restic repo initialized on Azure Blob: `restic snapshots --repo azure:backups:/homelab`
- [ ] Compose config valid: `docker compose config`
- [ ] `.env` file has credentials (not in version control)
- [ ] Systemd timer active: `sudo systemctl status restic-backup.timer`
- [ ] First backup completed: `journalctl -u restic-backup.service | tail`
- [ ] Restore procedure tested: files match source
- [ ] Repository integrity OK: `restic check`
