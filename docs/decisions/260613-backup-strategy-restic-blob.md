# Backup Strategy — Restic to Local SATA + Azure Blob

**Date:** 2026-06-13
**Status:** Implemented

---

## Context

The homelab's 256 GB SSD holds all service configurations, Docker volumes, and data. Drive failure means total data loss. A backup strategy is needed that covers: fast local recovery for day-to-day incidents, and off-site protection against fire/theft.

## Decision

Use **Restic** as the backup tool with a **dual-target** approach: primary backup to a local SATA disk, secondary copy to Azure Blob Storage for off-site protection.

Key factors:
- **Restic's deduplication** — highly effective for Docker volume snapshots (config files change little day-to-day), reducing storage costs on both local disk and Azure Blob
- **AES-256 encryption** — built into Restic; backups are encrypted before leaving the server, suitable for cloud storage
- **Local SATA disk** — one-time cost (~150–250 PLN for a 1 TB SSD in the free M910q 2.5" bay); fast local restore without internet dependency
- **Azure Blob off-site** — ~$0.018/GB/month; ~$0.90–1.80/month for 50–100 GB deduplicated; no per-server fee (vs Azure Backup MARS agent at $10/month for the protected instance alone)
- **Docker-native** — Restic runs as a container with a simple cron schedule

Rejected alternatives:
- **Azure Backup (MARS agent)** — $10/month protected instance fee + $0.0224/GB for storage; 5–10× the cost of Restic + Blob for this scale (see [research doc 14](../research/14-backup-cost-comparison.md))
- **Local-only backup** — no protection against fire, theft, or physical destruction of the server
- **Cloud-only backup** — restore requires internet download; slow for large volumes; monthly cloud egress costs if restoring frequently
- **rsync + cron** — no deduplication, no encryption built-in, no snapshot management
- **Borg** — equivalent to Restic in features but requires SSH access to the backup target; Restic's native REST API for Blob Storage is simpler

Retention policy: daily snapshots kept for 7 days, weekly for 4 weeks, monthly for 6 months.

## Consequences

- Fast local restore from SATA disk (minutes) for day-to-day incidents
- Off-site Azure Blob copy protects against physical loss but adds restore time (depends on internet speed)
- Restic repository format is self-contained — recovery only needs the Restic binary and the repository password, no proprietary tooling
- Deduplication means the Azure Blob storage cost stays low even as the dataset grows
- The secondary SATA disk must be replaced every 2–3 years or monitored via SMART
- No automatic integrity checking — periodic `restic check` needed to verify repository health
