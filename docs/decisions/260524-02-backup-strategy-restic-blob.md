# Backup Strategy — Restic to Local SATA + Azure Blob

**Date:** 2026-05-24  
**Last amended:** 2026-06-13  
**Status:** In Progress

---

## Context

The homelab's 256 GB SSD holds all service configurations, Docker volumes, and data. Drive failure means total data loss. A backup strategy is needed that covers off-site protection against fire/theft. Fast local recovery via a secondary SATA disk is planned but the disk has not yet been procured.

## Decision

Use **Restic** as the backup tool, backing up to Azure Blob Storage for off-site protection. A local SATA disk will be added later as a fast local restore target.

Key factors:
- **Restic's deduplication** — highly effective for Docker volume snapshots (config files change little day-to-day), reducing storage costs on Azure Blob
- **AES-256 encryption** — built into Restic; backups are encrypted before leaving the server, suitable for cloud storage
- **Azure Blob off-site** — ~$0.018/GB/month; ~$0.90–1.80/month for 50–100 GB deduplicated; no per-server fee (vs Azure Backup MARS agent at $10/month for the protected instance alone)
- **Deployment model — TBD** — Whether to run Restic as a native binary with systemd timer or as a Docker container is still being evaluated. The official binary includes the Azure Blob backend (the `apt` package does not); a container avoids this issue entirely

Rejected alternatives:
- **Azure Backup (MARS agent)** — $10/month protected instance fee + $0.0224/GB for storage; 5–10× the cost of Restic + Blob for this scale (see [research doc 14](../research/14-backup-cost-comparison.md))
- **Local-only backup** — no protection against fire, theft, or physical destruction of the server
- **Cloud-only backup** — restore requires internet download; slow for large volumes; monthly cloud egress costs if restoring frequently
- **rsync + cron** — no deduplication, no encryption built-in, no snapshot management
- **Borg** — equivalent to Restic in features but lacks a first-party Azure Blob backend; requires rclone as an intermediary. Restic's native Azure Blob backend is simpler

Retention policy: daily snapshots kept for 7 days, weekly for 4 weeks, monthly for 6 months.

## Consequences

- Off-site Azure Blob storage protects against physical loss but restore time depends on internet speed
- Restic repository format is self-contained — recovery only needs the Restic binary and the repository password, no proprietary tooling
- Deduplication means the Azure Blob storage cost stays low even as the dataset grows
- No automatic integrity checking — periodic `restic check` needed to verify repository health
- A future local SATA disk will add fast (minutes) recovery without internet dependency, but has not been procured yet
