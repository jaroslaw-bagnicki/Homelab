# Setup Runbooks

Step-by-step guides for configuring the homelab server.

| # | Runbook | Topic |
|---|---|---|
| 1 | [1-init.md](1-init.md) | Ubuntu install, static IP, SSH, LVM resize, mDNS, SSH key, hardening |
| 2 | [2-docker.md](2-docker.md) | Docker Engine + Portainer CE |
| 2a | [2a-ghcr-portainer.md](2a-ghcr-portainer.md) | GHCR registry in Portainer CE (supplements step 2) |
| 3 | [3-dns.md](3-dns.md) | Local DNS (DNSMasq) |
| 4 | [4-caddy.md](4-caddy.md) | Caddy reverse proxy with TLS |
| 4a | [4a-hello-world.md](4a-hello-world.md) | Hello World demo behind Caddy (supplements step 4) |
| 5 | [5-cloudflare-tunnel.md](5-cloudflare-tunnel.md) | Cloudflare Tunnel for public HTTPS access |
| 6 | [6-azure-arc.md](6-azure-arc.md) | Azure Arc hybrid server enrollment |
| 6a | [6a-azure-monitor.md](6a-azure-monitor.md) | Azure Monitor metrics and log collection (supplements step 6) |
| 7 | [7-restic-backup.md](7-restic-backup.md) | Restic backup to Azure Blob (native binary, systemd timer, Arc managed identity) |
| 9 | [9-mssql-dev.md](9-mssql-dev.md) | SQL Server Developer Edition in Docker |
| 10 | [10-vps-playground.md](10-vps-playground.md) | Contabo VPS initial setup — SSH hardening, UFW, fail2ban, Docker, Ansible target |
| 11 | [11-cntb-cli.md](11-cntb-cli.md) | Contabo CLI (`cntb`) — install, configure OAuth2, common commands, destroy/recreate workflow |
| 12 | [12-codespaces-devcontainer.md](12-codespaces-devcontainer.md) | GitHub Codespaces & Dev Container setup — browser-based dev, no local install |
| 13 | [13-copilot-desktop-setup.md](13-copilot-desktop-setup.md) | Copilot Desktop agentic dev environment — execution plan for issue #15 |
| 14 | [14-gh-codespaces-sp-for-homelab.md](14-gh-codespaces-sp-for-homelab.md) | GH Codespaces Service Principal for Homelab — bootstrap, KV persistence, rotation, Azure MCP auth — see [ADR 16](../decisions/16-gh-codespaces-sp-for-homelab.md) |
| 15 | [15-opencode-session-persistence.md](15-opencode-session-persistence.md) | OpenCode in Codespaces — session persistence + Azure Blob backup (survives Dev Container rebuilds and Codespace deletion), plus remote access from Desktop app / browser via `opencode web` |
| 16 | [16-docker-services-ansible-role.md](16-docker-services-ansible-role.md) | Ansible `docker_services` role — deploys Portainer, Caddy, and Hello World on Cloudlab via `docker_compose_v2` |
| 17 | [17-opencode-server-on-cloudlab.md](17-opencode-server-on-cloudlab.md) | Per-project OpenCode server instances on Cloudlab — `docker_opencode_ingress` + `docker_opencode_instances` roles, KV-backed `OPENCODE_SERVER_PASSWORD`, wildcard `*-oc.<domain>` routing via dedicated `caddy-opencode` — see [ADR 18](../decisions/18-opencode-docker-sandbox.md) |
