# Architecture Decision Log

[← Back to Home](../README.md)

---

Significant architectural and technology choices recorded in
[MADR](https://adr.github.io/madr/) format.

**Status values:** Proposed · Accepted · Implemented · Deferred · Superseded · Deprecated

> **Note:** ADRs were introduced in June 2026. Decisions made before that date
> are **not backfilled** — the original trade-off context is embedded in the
> relevant research docs and runbooks. This absence is expected, not a gap.

---

| Date | ADR | Status |
|------|-----|--------|
| 2026-06-16 | [Establish Lightweight ADR Log in MADR Format](260616-establish-adr-log.md) | Accepted |
| 2026-06-13 | [Ansible for Host Configuration Management](260613-ansible-host-config.md) | Accepted |
| 2026-06-13 | [Ticketing System — GitHub Issues](260613-ticketing-github-issues.md) | Implemented |
| 2026-05-24 (amended 2026-06-13) | [Backup Strategy — Restic to Local SATA + Azure Blob](260524-backup-strategy-restic-blob.md) | In Progress |
| 2026-06-02 | [Azure Monitor via Arc for Homelab Monitoring](260602-azure-monitor-via-arc.md) | Implemented |
| 2026-05-24 | [Hybrid Cloud Strategy — Physical Homelab + Minimal Azure](260524-hybrid-cloud-azure-arc.md) | Implemented |
| 2026-05-30 | [Remote Access — Cloudflare Tunnel for Inbound HTTPS](260530-remote-access-cloudflare-tunnel.md) | Implemented |
| 2026-05-29 | [Reverse Proxy — Caddy with Auto-TLS and CaC](260529-reverse-proxy-caddy.md) | Implemented |
| 2026-05-29 | [Local DNS — DNSMasq with Wildcard `.home` Domains](260529-local-dns-dnsmasq.md) | Implemented |
| 2026-05-24 | [Container Strategy — Docker Compose First, k3s Path](260524-container-strategy.md) | Implemented |
| 2026-05-24 | [OS Decision — Ubuntu Server 24.04 LTS](260524-os-decision-ubuntu-server.md) | Implemented |
| 2026-05-20 | [Hardware Selection — Lenovo ThinkCentre M910q Tiny](260520-hardware-selection-m910q.md) | Implemented |
