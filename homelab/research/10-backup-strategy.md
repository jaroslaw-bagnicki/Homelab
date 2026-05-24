# 10 — Backup Strategy

**Source**: Derived from doc 05, May 24 2026  
**Scope**: Backup target, tool selection, Restic configuration, retention schedule, disaster recovery

---

## Backup Target

The 256 GB SSD holds all service data. Without a backup plan, drive failure = total loss. Use the free 2.5" SATA bay in the M910q for a mirrored backup disk.

### Hardware setup

Install a 1 TB HDD or SSD in the secondary 2.5" SATA bay. This gives a full local mirror with no ongoing cloud cost.

### Backup tool: Restic

[Restic](https://restic.net) is a fast, encrypted, deduplicating backup client. Runs as a container with a simple cron schedule.

```bash
# ~/homelab/backups/docker-compose.yml
services:
  restic:
    image: restic/restic:latest
    container_name: restic-backup
    restart: unless-stopped
    environment:
      - RESTIC_PASSWORD=YOUR_STRONG_PASSWORD
      - BACKUP_RETENTION=--keep-daily=7 --keep-weekly=4 --keep-monthly=6
    volumes:
      - /home/ubuntu/homelab:/data:ro    # read-only mount of homelab dir
      - /mnt/backup-disk:/backups         # secondary SATA disk
    volumes_from:
      - postgres_db:/mnt/backup-disk/postgres:ro
    command: >
      backup /data
      --repo /backups/homelab
      $BACKUP_RETENTION
```

### What to back up

| Data | Priority | Notes |
|---|---|---|
| `~/homelab/` (all service configs + data volumes) | High | Everything in one portable folder |
| PostgreSQL data directory | High | Included via volume read-only bind mount |
| Ollama models (Phase 2) | Medium | Large — skip if disk is tight; models can be re-pulled |
| Gitea repository data | High | Bare git repos, attachments |

### Retention

- **Daily** — last 7 days
- **Weekly** — last 4 weeks
- **Monthly** — last 6 months

> Replace the secondary disk every 2–3 years or check SMART status quarterly with `smartctl`.

---

## Restic vs Azure Backup

| Concern | Restic (local SATA) | Azure Backup (MARS agent) |
|---|---|---|
| Backup target | Secondary SATA disk in M910q | Azure Recovery Services vault (cloud) |
| Cost | One-time disk purchase (~150–250 PLN for 1 TB SSD) | Azure Vault storage ~€5–10/month |
| Internet required | ❌ No (local only) | ✅ Yes — always-on connection |
| Offline recovery | ✅ Yes — disk is local | ⚠️ Need internet + Azure portal to restore |
| Setup complexity | Low — one Docker container | Medium — Azure subscription, vault, agent |
| Encryption | ✅ AES-256 restic built-in | ✅ Microsoft-managed keys |
| Retention | User-defined (daily/weekly/monthly) | Azure policy (daily/weekly/monthly) |
| dedup | ✅ Yes | ✅ Yes |
| Speed | Fast — local SATA | Depends on upload bandwidth |
| Arc dependency | None | None (works without Arc) |
| Best for | Fast recovery, no cloud cost, offline scenario | Offsite disaster recovery, multi-machine fleet |

## Middle Option: Restic → Local Disk + Azure Blob Offsite Copy

**Concept**: Primary backup stays on local SATA disk (fast restore). A scheduled cron job runs a second Restic backup pass to Azure Blob Storage for offsite protection against fire/theft.

**How it works**: Restic uses a [repository on Azure Blob Storage](https://restic.readthedocs.io/en/latest/045_backups_tuning_backup_parameters.html#backups-to-microsoft-azure-blob-storage) via the Azure native REST backend — no rclone needed.

```bash
# Environment for Azure Blob-backed restic repo
export AZURE_STORAGE_ACCOUNT="yourstorageaccount"
export AZURE_STORAGE_KEY="your-storage-key"

# Backup to Azure Blob (georedundant by default)
restic backup /data \
  --repo "azure:container-name:/backups/homelab" \
  $BACKUP_RETENTION
```

**Cost comparison (Azure Blob Storage — LRS)**

| Usage | Price (North Europe) |
|---|---|
| 200 GB × €0.02 / GB / month | ~€4 / month |
| 500 GB × €0.02 / GB / month | ~€10 / month |
| 1 TB × €0.02 / GB / month | ~€20 / month |

**vs Azure Backup full agent**:
- Azure Backup = ~€9–13/month (instance + storage)
- Azure Blob alone = ~€4–20/month for 200 GB–1 TB (storage only, no agent management)

| Concern | Restic → Blob | Azure Backup (MARS) |
|---|---|---|
| Cost | ~€4–10/month (blob only) | ~€9–13/month (instance + storage) |
| Management | Manual cron + restic | Azure Vault + agent |
| Retention | Restic policy (in-repo) | Azure policy |
| Encryption | AES-256 (restic) | Microsoft-managed |
| Arc dependency | None | None |
| Backup complexity | Medium — env vars + cron | Low — agent installer |

**Verdict**: Restic → local disk + optional Azure Blob upload is the best of both worlds — fast local restore, cheap offsite copy. Azure Backup adds unnecessary vault management overhead for a single-node homelab.

To schedule the blob upload, add a second container or cron service:

```yaml
services:
  restic-local:
    image: restic/restic:latest
    container_name: restic-backup
    restart: unless-stopped
    volumes:
      - /home/ubuntu/homelab:/data:ro
      - /mnt/backup-disk:/backups
    environment:
      - RESTIC_PASSWORD=YOUR_STRONG_PASSWORD
    command: >
      backup /data --repo /backups/homelab
      --keep-daily=7 --keep-weekly=4 --keep-monthly=6

  restic-azure:
    image: restic/restic:latest
    container_name: restic-azure-backup
    restart: unless-stopped
    volumes:
      - /home/ubuntu/homelab:/data:ro
    environment:
      - RESTIC_PASSWORD=YOUR_STRONG_PASSWORD
      - AZURE_STORAGE_ACCOUNT=yourstorageaccount
      - AZURE_STORAGE_KEY=your-storage-key
    volumes_from: []
    command: >
      backup /data
      --repo "azure:container-name:/backups/homelab"
      --keep-daily=7 --keep-weekly=4 --keep-monthly=6
    # Run weekly only via external cron or label
    profiles:
      - offsite
```

Run `restic-azure` on a weekly cron schedule to avoid daily upload costs.

---

Once Azure Arc is enrolled, Azure Backup can layer on top for cloud-offsite redundancy:

| Capability | Without Arc | With Arc |
|---|---|---|
| Azure Backup (MARS agent) | ✅ Works | ✅ Works |
| Azure Backup Center (unified management) | ❌ Not available | ✅ Yes |
| Backup policy via Azure Policy | ❌ Not available | ✅ Yes |

Azure Arc enrollment is **not required** for Azure Backup to function — it only adds a unified management view across machines. For a single-node homelab, Restic to local SATA disk is the primary plan; Azure cloud backup is optional post-Arc.

---

## Disaster Recovery

| Scenario | Response |
|---|---|
| Primary SSD failure | Swap in backup disk, restore from restic snapshot |
| Accidental deletion | `restic restore latest --target /recovery /backups/homelab` |
| Secondary disk failure | Replace disk, run restic check, re-backup |
| Full homelab loss | New M910q + Ubuntu, re-pull compose stacks, restic restore |