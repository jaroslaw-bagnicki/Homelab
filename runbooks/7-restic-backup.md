# Homelab Setup — Restic Backup

> Runbook for deploying Restic backup with local SATA disk storage and optional Azure Blob offsite copy.

## Prerequisites

- [ ] Secondary SATA disk installed in the M910q's 2.5" bay (see [research](../research/10-backup-strategy.md#hardware-setup))
- [ ] Docker Engine + Compose running (see [2-docker.md](2-docker.md))
- [ ] SSH access via `ssh jarek@homelab.local`

---

## 1. Prepare the Backup Disk

### 1.1 Identify the secondary disk

```bash
lsblk
```

Look for a disk that is **not** your 256 GB NVMe/SSD. On the M910q, the primary disk is typically `/dev/nvme0n1` and the SATA bay appears as `/dev/sda`.

### 1.2 Partition and format

> **Warning**: Double-check the device name — the wrong device will wipe your OS disk.

```bash
sudo fdisk /dev/sda
```

In `fdisk`:
1. Type `n` (new partition)
2. Accept defaults for partition number, first sector, and last sector
3. Type `w` to write and exit

Then format as ext4:

```bash
sudo mkfs.ext4 /dev/sda1
```

### 1.3 Get the disk UUID

```bash
sudo blkid /dev/sda1
```

Copy the UUID (e.g. `a1b2c3d4-...`).

### 1.4 Add to fstab

```bash
sudo nano /etc/fstab
```

Add a line:

```
UUID=a1b2c3d4-...  /mnt/backup-disk  ext4  defaults,nofail  0  2
```

> Replace the UUID with the one from `blkid`. The `nofail` option lets the system boot even if the disk is missing.

### 1.5 Create mount point and mount

```bash
sudo mkdir -p /mnt/backup-disk
sudo mount -a
```

### 1.6 Verify

```bash
df -h /mnt/backup-disk
```

Expected: device `/dev/sda1` mounted at `/mnt/backup-disk`.

---

## 2. Initialize the Restic Repository

Pull the Restic image and create the repository:

```bash
sudo docker run --rm \
  -v /mnt/backup-disk:/backups \
  restic/restic:latest \
  init --repo /backups/homelab
```

You'll be prompted for a **repository password**. Choose a strong one and store it in your password manager — you'll need it for every restore.

> **Security note**: The `RESTIC_PASSWORD` environment variable (set in step 3) lets Restic open the repo automatically. If someone gains access to the container they can read backups. For a homelab on a trusted LAN this is acceptable.

### Verify

```bash
sudo docker run --rm \
  -v /mnt/backup-disk:/backups \
  restic/restic:latest \
  snapshots --repo /backups/homelab
```

Enter the password. Expected output: `no snapshots found` (or an empty list).

---

## 3. Add Restic to Docker Compose

All commands run from `/opt/docker/`.

### 3.1 Create a `.env` file for the password

```bash
nano /opt/docker/.env
```

Add:

```env
RESTIC_PASSWORD=your-strong-password
```

> Replace with the password from step 2, or generate a new one with `openssl rand -base64 32`.

### 3.2 Add the Restic service

```bash
nano docker-compose.yml
```

Append under `services:`:

```yaml
  restic-backup:
    image: restic/restic:latest
    container_name: restic-backup
    profiles:
      - backup
    env_file:
      - .env
    volumes:
      - /opt/docker:/data/homelab-config:ro
      - /var/lib/docker/volumes:/data/docker-volumes:ro
      - /mnt/backup-disk:/backups
    command: >
      backup /data
      --repo /backups/homelab
      --keep-daily=7 --keep-weekly=4 --keep-monthly=6
      --exclude /data/docker-volumes/portainer_data/*
```

> **What's backed up**: The entire `/opt/docker/` directory (compose files, Caddyfile, configs) and all Docker volumes (service data, databases). The Portainer volume is excluded from its internal data since Portainer manages its own snapshots.

### 3.3 Add the Azure offsite service (optional)

Append under `services:` (after `restic-backup`):

```yaml
  restic-azure:
    image: restic/restic:latest
    container_name: restic-azure
    profiles:
      - backup
      - offsite
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

And to the `.env` file:

```env
AZURE_STORAGE_ACCOUNT=yourstorageaccount
AZURE_STORAGE_KEY=your-storage-key
```

> The `restic-azure` service has the `offsite` profile. Run it separately on a weekly schedule (see step 5).

---

## 4. Schedule Daily Backups (Systemd Timer)

Use a systemd timer to run `restic-backup` every day.

### 4.1 Create the service unit

```bash
sudo nano /etc/systemd/system/restic-backup.service
```

```ini
[Unit]
Description=Restic backup — daily snapshot to local SATA disk
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/docker
ExecStart=/usr/bin/docker compose run --rm restic-backup
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
Description=Daily Restic backup
Requires=restic-backup.service

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

> `RandomizedDelaySec=1h` spreads the backup time across the day to avoid load spikes. `Persistent=true` runs a missed backup immediately after boot.

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

### 4.5 Run a manual backup (optional)

```bash
sudo systemctl start restic-backup.service
```

Check the status:

```bash
sudo systemctl status restic-backup.service
```

Or inspect the logs:

```bash
journalctl -u restic-backup.service
```

---

## 5. Optional: Schedule Weekly Azure Offsite

If you configured the `restic-azure` service, create a weekly timer.

### 5.1 Create the service unit

```bash
sudo nano /etc/systemd/system/restic-azure.service
```

```ini
[Unit]
Description=Restic backup — weekly snapshot to Azure Blob
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/docker
ExecStart=/usr/bin/docker compose run --rm restic-azure
User=jarek
Group=docker

[Install]
WantedBy=multi-user.target
```

### 5.2 Create the timer unit

```bash
sudo nano /etc/systemd/system/restic-azure.timer
```

```ini
[Unit]
Description=Weekly Restic Azure backup
Requires=restic-azure.service

[Timer]
OnCalendar=weekly
RandomizedDelaySec=6h
Persistent=true

[Install]
WantedBy=timers.target
```

### 5.3 Enable and start

```bash
sudo systemctl daemon-reload
sudo systemctl enable restic-azure.timer
sudo systemctl start restic-azure.timer
```

---

## 6. Test Restore Procedure

### 6.1 List snapshots

```bash
sudo docker run --rm \
  -v /mnt/backup-disk:/backups \
  --env-file /opt/docker/.env \
  restic/restic:latest \
  snapshots --repo /backups/homelab
```

### 6.2 Restore to a temporary directory

```bash
sudo docker run --rm \
  -v /mnt/backup-disk:/backups \
  -v /tmp/restic-restore:/restore \
  --env-file /opt/docker/.env \
  restic/restic:latest \
  restore latest --target /restore --repo /backups/homelab
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
sudo docker run --rm \
  -v /mnt/backup-disk:/backups \
  --env-file /opt/docker/.env \
  restic/restic:latest \
  check --repo /backups/homelab
```

Run `check` quarterly to detect bit-rot or disk errors.

---

## 7. Maintenance

| Action | Frequency | Command |
|---|---|---|
| List snapshots | As needed | `sudo docker run --rm -v /mnt/backup-disk:/backups --env-file /opt/docker/.env restic/restic:latest snapshots --repo /backups/homelab` |
| Check repo integrity | Quarterly | `sudo docker run --rm -v /mnt/backup-disk:/backups --env-file /opt/docker/.env restic/restic:latest check --repo /backups/homelab --read-data` |
| Prune old snapshots | Auto (retention flags in command) | Restic keeps 7 daily, 4 weekly, 6 monthly |
| SMART check | Quarterly | `sudo smartctl -H /dev/sda` |
| Replace backup disk | Every 2–3 years | Follow step 1 for new disk, then `restic restore` from old disk |

> `--read-data` in `check` reads every pack file — it's I/O intensive. Run during low usage.

---

## Verification Checklist

- [ ] Backup disk mounted: `df -h /mnt/backup-disk`
- [ ] Restic repo initialized: `restic snapshots --repo /backups/homelab`
- [ ] Compose config valid: `docker compose config`
- [ ] Systemd timer active: `sudo systemctl status restic-backup.timer`
- [ ] First backup completed: `journalctl -u restic-backup.service | tail`
- [ ] Restore procedure tested: files match source
- [ ] Repository integrity OK: `restic check`
- [ ] (Optional) Azure Blob repo initialized
- [ ] (Optional) Azure timer active: `sudo systemctl status restic-azure.timer`
