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