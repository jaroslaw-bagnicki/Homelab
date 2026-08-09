# Architecture Decision Log

[← Back to Home](../README.md)

---

Significant architectural and technology choices recorded in
[MADR](https://adr.github.io/madr/) format.

**Status values:** Proposed · Accepted · Implemented · Deferred · Superseded · Deprecated

---

| # | Date | ADR | Status |
|---|------|-----|--------|
| 24 | 2026-08-09 | [Edge Ingress on a Dedicated Thin-Client Appliance](24-edge-ingress-appliance.md) | Accepted |
| 22 | 2026-07-26 | [Migrate Homelab Workloads to Kubernetes (k3s + Azure Arc)](22-k3s-arc-homelab.md) | Accepted |
| 21 | 2026-07-16 | [Per-Project OpenCode Container Images](21-opencode-instance-images.md) | Accepted |
| 20 | 2026-07-05 | [Caddy as Single Routing Layer on Cloudlab](20-caddy-single-routing-layer.md) | Accepted |
| 19 | 2026-07-05 | [HTTPS-only origin via Cloudflare Tunnel + Cloudflare Origin CA on Cloudlab](19-cloudflare-tunnel-https-origin.md) | Accepted |
| 18 | 2026-07-11 | [Host OpenCode Server Instances on Homelab](18-opencode-sandbox.md) | Accepted |
| 17 | 2026-06-28 | [Adopt OpenCode for Agentic Homelab Development](17-adopt-opencode.md) | Implemented |
| 16 | 2026-06-28 | [Non-Interactive Agent Workload Identity Pattern](16-agent-identity-pattern.md) | Implemented |
| 15 | 2026-06-25 | [Evaluate GitHub Copilot Desktop for Agentic Development](15-copilot-desktop-agentic.md) | Deferred |
| 14 | 2026-06-18 | [Adopt GitHub Codespaces for Occasional Remote Work](14-codespaces-adoption.md) | Implemented |
| 13 | 2026-06-16 | [Use Contabo Cloud VPS 10 as Staging Environment for Homelab](13-cloudlab-staging.md) | Implemented |
| 12 | 2026-06-16 | [Establish Lightweight ADR Log in MADR Format](12-establish-adr-log.md) | Implemented |
| 11 | 2026-06-13 | [Ticketing System — GitHub Issues](11-ticketing-github-issues.md) | Implemented |
| 10 | 2026-06-13 | [Ansible for Host Configuration Management](10-ansible-host-config.md) | Implemented |
| 9 | 2026-06-02 | [Azure Monitor via Arc for Homelab Monitoring](09-azure-monitor-via-arc.md) | Implemented (partial) |
| 8 | 2026-05-30 | [Remote Access — Cloudflare Tunnel for Inbound HTTPS](08-remote-access-cloudflare-tunnel.md) | Superseded by [ADR 19](19-cloudflare-tunnel-https-origin.md) |
| 7 | 2026-05-29 | [Reverse Proxy — Caddy with Auto-TLS and Configuration-as-Code](07-reverse-proxy-caddy.md) | Implemented |
| 6 | 2026-05-29 | [Local DNS Resolution — DNSMasq with Wildcard `.home` Domains](06-local-dns-dnsmasq.md) | Implemented |
| 5 | 2026-05-24 | [OS Decision — Ubuntu Server 24.04 LTS](05-os-decision-ubuntu-server.md) | Implemented |
| 4 | 2026-05-24 | [Hybrid Cloud Strategy — Physical Homelab + Minimal Azure](04-hybrid-cloud-azure-arc.md) | Implemented |
| 3 | 2026-05-24 | [Container Strategy — Docker Compose First, k3s Migration Path](03-container-strategy.md) | Superseded by [ADR 22](22-k3s-arc-homelab.md) |
| 2 | 2026-05-24 | [Backup Strategy — Restic to Local SATA + Azure Blob](02-backup-strategy-restic-blob.md) | In Progress |
| 1 | 2026-05-20 | [Hardware Selection — Lenovo ThinkCentre M910q Tiny](01-hardware-selection-m910q.md) | Implemented |
