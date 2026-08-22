# Setup Runbooks

Step-by-step guides for configuring the homelab server.

| # | Runbook | Topic |
|---|---|---|
| 26 | [26-ml110-nas-exports.md](26-ml110-nas-exports.md) | ML110 NAS Phase 2 — SMB `/shared` backup share (SMB3 transport encryption required, `rescuezilla` user — unblocks #79); NFS `/export/backups` + Longhorn pending (with k3s, #44) — see [ADR 23](../decisions/23-nas-on-ml110.md) & [issue #62](https://github.com/jaroslaw-bagnicki/Homelab/issues/62) |
| 25 | [25-m910q-os-refresh.md](25-m910q-os-refresh.md) | M910q OS refresh — reinstall Ubuntu 24.04 LTS (ADR 05), Ansible base provision, Azure Arc enrolment; DNS/Caddy/tunnel move to the edge appliance — see [issue #74](https://github.com/jaroslaw-bagnicki/Homelab/issues/74) |
| 24 | [24-edge-appliance.md](24-edge-appliance.md) | Dedicated edge appliance (Dell Wyse 3040) — bare-metal cloudflared + Caddy + dnsmasq + Netdata as the single public ingress and local DNS; hardware audit complete (research 28); Debian minimal install on the eMMC — see [ADR 24](../decisions/24-edge-ingress-appliance.md) & [issue #65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) |
| 23 | [23-ml110-omv-setup.md](23-ml110-omv-setup.md) | ML110 NAS Phase 1 — OMV 8.x install on the Goodram SSD, BIOS AHCI, mdadm RAID1 (`md0`/`md1`), static IP `192.168.2.210` — see [ADR 23](../decisions/23-nas-on-ml110.md) & [issue #61](https://github.com/jaroslaw-bagnicki/Homelab/issues/61) |
| 22 | [22-ml110-nas-inventory.md](22-ml110-nas-inventory.md) | Phase 0 inventory & FreeNAS state audit on the HP ProLiant ML110 before OMV install — generation, ZFS pools, disk SMART, controller topology, BIOS settings — see [idea 03](../ideas/03-nas-backup-target-ml110.md) & [issue #54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) |
| 21 | [21-tl-sg108e-switch.md](21-tl-sg108e-switch.md) | TL-SG108E homelab switch setup — wiring, management IP, QoS/rate-limit, IGMP snooping, optional port mirroring — see [research 24](../research/24-network-topology-design.md) & [issue #55](https://github.com/jaroslaw-bagnicki/Homelab/issues/55) |
| 20 | [20-deploy-zot.md](20-deploy-zot.md) | Self-hosted Zot OCI registry on cloudlab — htpasswd auth from AKV, pull-through cache for GHCR/mcr/Docker Hub, public at `zot.<domain>` via Cloudflare Tunnel + Caddy — see [issue #50](https://github.com/jaroslaw-bagnicki/Homelab/issues/50) |
| 19 | [19-azure-sp-for-opencode.md](19-azure-sp-for-opencode.md) | Per-instance Azure service principal for OpenCode instances — `homelab-oc-agent-sp` bootstrap, AKV-sourced `AZURE_*` env vars injected by Ansible, rotation, troubleshooting — see [ADR 16](../decisions/16-agent-identity-pattern.md) · [issue #40](https://github.com/jaroslaw-bagnicki/Homelab/issues/40) |
| 18 | [18-provision-opencode-instance.md](18-provision-opencode-instance.md) | Provisioning a new OpenCode instance — adding to inventory, AKV secret, deploy, model provider setup, persistence, security notes — see [issue #37](https://github.com/jaroslaw-bagnicki/Homelab/issues/37) |
| 17 | [17-deploy-opencode-on-cloudlab.md](17-deploy-opencode-on-cloudlab.md) | Per-project OpenCode server instances on Cloudlab — `docker_opencode_ingress` + `docker_opencode_instances` roles, KV-backed `OPENCODE_SERVER_PASSWORD`, wildcard `*-oc.<domain>` routing via dedicated `caddy-opencode` — see [ADR 18](../decisions/18-opencode-sandbox.md) |
| 16 | [16-docker-services-ansible-role.md](16-docker-services-ansible-role.md) | Ansible `docker_services` role — deploys Portainer, Caddy, and Hello World on Cloudlab via `docker_compose_v2` |
| 15 | [15-opencode-session-persistence.md](15-opencode-session-persistence.md) | OpenCode in Codespaces — session persistence + Azure Blob backup (survives Dev Container rebuilds and Codespace deletion), plus remote access from Desktop app / browser via `opencode web` |
| 14 | [14-gh-codespaces-sp-for-homelab.md](14-gh-codespaces-sp-for-homelab.md) | GH Codespaces Service Principal for Homelab — bootstrap, KV persistence, rotation, Azure MCP auth — see [ADR 16](../decisions/16-agent-identity-pattern.md) |
| 13 | [13-copilot-desktop-setup.md](13-copilot-desktop-setup.md) | Copilot Desktop agentic dev environment — execution plan for issue #15 |
| 12 | [12-codespaces-devcontainer.md](12-codespaces-devcontainer.md) | GitHub Codespaces & Dev Container setup — browser-based dev, no local install |
| 11 | [11-cntb-cli.md](11-cntb-cli.md) | Contabo CLI (`cntb`) — install, configure OAuth2, common commands, destroy/recreate workflow |
| 10 | [10-vps-playground.md](10-vps-playground.md) | Contabo VPS initial setup — SSH hardening, UFW, fail2ban, Docker, Ansible target |
| 09 | [09-mssql-dev.md](09-mssql-dev.md) | SQL Server Developer Edition in Docker |
| 07 | [07-restic-backup.md](07-restic-backup.md) | Restic backup to Azure Blob (native binary, systemd timer, Arc managed identity) |
| 06a | [06a-azure-monitor.md](06a-azure-monitor.md) | Azure Monitor metrics and log collection (supplements step 6) |
| 06 | [06-azure-arc.md](06-azure-arc.md) | Azure Arc hybrid server enrollment |
| 05 | [05-cloudflare-tunnel.md](05-cloudflare-tunnel.md) | Cloudflare Tunnel for public HTTPS access |
| 04a | [04a-hello-world.md](04a-hello-world.md) | Hello World demo behind Caddy (supplements step 4) |
| 04 | [04-caddy.md](04-caddy.md) | Caddy reverse proxy with TLS |
| 03 | [03-dns.md](03-dns.md) | Local DNS (DNSMasq) |
| 02a | [02a-ghcr-portainer.md](02a-ghcr-portainer.md) | Container registries in Portainer CE: GHCR + self-hosted Zot (supplements step 2) |
| 02 | [02-docker.md](02-docker.md) | Docker Engine + Portainer CE |
| 01 | [01-init.md](01-init.md) | Ubuntu install, static IP, SSH, LVM resize, mDNS, SSH key, hardening |
