# Homelab Setup — Restic Backup (Azure Blob)

> Runbook for deploying Restic backup to Azure Blob Storage — no local disk required.

## Prerequisites

- [ ] Docker Engine + Compose running (see [2-docker.md](2-docker.md))
- [ ] SSH access via `ssh jarek@homelab.local`
- [ ] Azure subscription (any region) + `Az` PowerShell module installed on your local machine

---

## 1. Provision the Azure Storage Account and Container

### 1.1 Create a resource group (if needed)

Run from your laptop or a machine with the Az PowerShell module installed:

```powershell
Connect-AzAccount
New-AzResourceGroup -Name rg-homelab-backup -Location polandcentral
```

> Change `-Location` if you prefer a different Azure region.

### 1.2 Create the storage account

```powershell
New-AzStorageAccount -ResourceGroupName rg-homelab-backup `
  -Name "sthomelabbackup" `
  -SkuName Standard_LRS `
  -Kind StorageV2 `
  -AccessTier Cool
```

Requirements met by this command:
- **Account kind**: StorageV2
- **Performance**: Standard (default)
- **Replication**: LRS
- **Tier**: Cool

> Pick a globally unique storage account name (e.g. `st<your initials>homelabbackup`).

### 1.3 Create the `backups` container

```powershell
$ctx = (Get-AzStorageAccount -ResourceGroupName rg-homelab-backup -Name "sthomelabbackup").Context
New-AzStorageContainer -Name backups -Context $ctx -Permission Off
```

`-Permission Off` means private — no anonymous access.

### 1.4 Retrieve the storage account key

```powershell
Get-AzStorageAccountKey -ResourceGroupName rg-homelab-backup -Name "sthomelabbackup" `
  | Select-Object -First 1 -ExpandProperty Value
```

Save the output — you'll need the **storage account name** and this **key** for step 2.

> Alternatively, copy the key from the Azure Portal: storage account → **Access keys** → copy either key1 or key2.

---

## 2. Initialize the Restic Repository on Azure Blob

Pull the Restic image and create the repository directly on Azure Blob:

```bash
sudo docker run --rm \
  -e AZURE_STORAGE_ACCOUNT=yourstorageaccount \
  -e AZURE_STORAGE_KEY="your-storage-key" \
  restic/restic:latest \
  init --repo azure:backups:/homelab
```

You'll be prompted for a **repository password**. Choose a strong one and store it in your password manager — you'll need it for every restore.

> **Security note**: The `RESTIC_PASSWORD` + `AZURE_STORAGE_KEY` environment variables (set in step 3) let Restic open the repo automatically. Keep the `.env` file safe.

### Verify

```bash
sudo docker run --rm \
  -e AZURE_STORAGE_ACCOUNT=yourstorageaccount \
  -e AZURE_STORAGE_KEY="your-storage-key" \
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
AZURE_STORAGE_ACCOUNT=yourstorageaccount
AZURE_STORAGE_KEY=your-storage-key
```

> Generate a strong password: `openssl rand -base64 32`

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
      - AZURE_STORAGE_KEY=${AZURE_STORAGE_KEY}
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
  -e AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT} \
  -e AZURE_STORAGE_KEY=${AZURE_STORAGE_KEY} \
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

## 7. Cost Estimates (Azure Blob Cool — LRS)

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
