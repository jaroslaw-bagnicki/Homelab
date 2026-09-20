# Changelog

Notable changes to the Homelab repo, newest first. This log supersedes the
"What's Done" table that used to live in the root `README.md`. Entries carry a
`(type)` prefix describing what the change delivers — `feat`, `fix`, `docs`, `chore`, `refactor`.

**One line per entry, one entry per workstream.** State what changed and link one artefact — the
rationale, measurements and configuration detail live in the linked ADR, runbook or report. Headline
plus at most one clause, under ~200 characters: if it will not fit on one line, it is not a changelog
entry. Notable changes only: no instruction-file tweaks, typo/link fixes, cross-reference or rename
corrections, or changelog bookkeeping.
Entries sit under `## YYYY‑MM` headings — non-breaking hyphen, newest month and newest entry first.

## 2026‑09

- **(docs)** Add ADR 34 — LAN services are TLS-only, no plaintext HTTP — [ADR 34](docs/decisions/34-lan-tls-only.md)
- **(feat)** Netdata Tier B — `netdata` role (parent/child), Parent host-native on `pve` behind an **HTTPS-only dashboard** with TLS-only streaming — [runbook 31](docs/runbooks/31-deploy-netdata.md)
- **(docs)** Rename the Wyse 5070 node `ha` → `pve` — hostnames name the host role, not a guest — [ADR 33](docs/decisions/33-fleet-node-hostnames.md)
- **(docs)** Add ADR 32 — no hosted CI — [ADR 32](docs/decisions/32-no-hosted-ci.md)
- **(docs)** Add the `quality-assessment` prompt and the first repo assessment — [report](docs/reports/260913-quality-assessment.md)
- **(feat)** UPS graceful shutdown via **NUT** — LXC 213 server, `nut_client` clients, and a real-outage drill (**52 min 53 s** to `LB`) — [report](docs/reports/260919-nut-shutdown-drill.md)
- **(docs)** Re-cut the static address scheme — `20x` servers, `21x` guests, **VMID = last octet** — [ADR 31](docs/decisions/31-static-address-scheme.md)
- **(docs)** Wincor Beetle M-III is the NAS successor on OMV, superseding the ML110 — [ADR 29](docs/decisions/29-nas-backup-target-beetle-m3-omv.md)
- **(docs)** Make `overview.md` "What's Next" a state-grouped board with a `Not Scheduled` parking lot — [overview](docs/overview.md)
- **(docs)** Add idea 09 — shared-rail UPS with NUT-driven shutdown — [idea 09](docs/ideas/09-ups-nut-home-assistant.md)
- **(feat)** Proxmox VE host (Wyse 5070) — **9.2.2** installed and base provisioned — [runbook 28](docs/runbooks/28-pve-proxmox-node.md)
- **(feat)** Fleet SSH access restricted to the LAN, with devcontainer key autoload — [runbook 24](docs/runbooks/24-edge-appliance.md)
- **(docs)** Futro S930 hardware diagnostic — OPNsense router candidate — [research 31](docs/research/31-futro-s930-hardware-diagnostic.md)

## 2026‑08

- **(feat)** Edge ingress appliance (Wyse 3040) — Debian install, `edge_host` role and backup/restore runbook — [ADR 24](docs/decisions/24-edge-ingress-appliance.md) · [runbook 24](docs/runbooks/24-edge-appliance.md)
- **(docs)** LTE/5G WAN failover — idea + mobile-offer research — [idea 08](docs/ideas/08-lte-wan-failover.md) · [research 30](docs/research/30-mobile-internet-failover-offers.md)
- **(docs)** NAS backup-target variants — EliteDesk 800 G1 and Wincor Beetle M-III ideas — [idea 01b](docs/ideas/01b-nas-backup-target-elitedesk.md) · [idea 01c](docs/ideas/01c-nas-backup-target-wincor-beetle.md)
- **(docs)** Add idea 07 — OPNsense router on a Fujitsu Futro S930 — [idea 07](docs/ideas/07-opnsense-futro-s930.md)
- **(docs)** Wyse 5070 hardware diagnostic — J4105, 8 GB DDR4, 128 GB M.2 SATA, no NVMe — [research 29](docs/research/29-wyse5070-hardware-diagnostic.md)
- **(feat)** Fleet-wide SSH automation key (`fleetadm@homelab`, Key Vault-backed) — [ADR 28](docs/decisions/28-fleet-admin-account-and-key.md)
- **(feat)** ML110 NAS — OMV install with mdadm RAID1 and the SMB backup share — [ADR 23](docs/decisions/23-nas-on-ml110.md) · [runbook 23](docs/runbooks/23-ml110-omv-setup.md)
- **(feat)** M910q OS refresh — Ubuntu 24.04 reinstall, Ansible base provision and Arc enrolment — [runbook 25](docs/runbooks/25-m910q-os-refresh.md)
- **(docs)** Add ADR 27 — two-tier monitoring: Azure Monitor via Arc + a local Netdata tier — [ADR 27](docs/decisions/27-monitoring-strategy.md)
- **(docs)** Zigbee energy monitoring via Zigbee2MQTT → Prometheus — [ADR 26](docs/decisions/26-zigbee-energy-monitoring.md)
- **(docs)** Add `overview.md` (state + roadmap) and `hardware.md` (per-node inventory) — [overview](docs/overview.md) · [hardware](docs/hardware.md)
- **(docs)** Home Assistant on a dedicated thin-client node (Proxmox VM) — [ADR 25](docs/decisions/25-home-assistant-thin-client.md)
- **(docs)** Homelab network topology & design — flat-vs-VLAN analysis and static IP scheme — [research 24](docs/research/24-network-topology-design.md)
- **(feat)** TL-SG108E switch setup — wiring, QoS and IGMP snooping — [runbook 21](docs/runbooks/21-tl-sg108e-switch.md)
- **(feat)** Build per-project OpenCode images and push them to Zot — [ADR 21](docs/decisions/21-opencode-instance-images.md)
- **(feat)** Adopt Zot as self-hosted OCI registry with pull-through cache — [runbook 20](docs/runbooks/20-deploy-zot.md)
- **(feat)** Configure MCP servers per OpenCode instance (GitHub PAT, Azure) — [runbook 18](docs/runbooks/18-provision-opencode-instance.md)
- **(docs)** Add ideas: DevPod DevContainers for OpenCode and a NAS backup target — [ideas](docs/ideas/README.md)
- **(chore)** Drop the `(type)` prefix from issue and PR titles — labels convey the type
- **(docs)** Adopt "research settles, ADR owns" co-authoring pattern — research/idea docs defer decision authority to the ADR

## 2026‑07

- **(feat)** Provision `homelab-oc` Azure service principal for OpenCode instances — AKV-sourced `AZURE_*` env vars — [runbook 19](docs/runbooks/19-azure-sp-for-opencode.md) · [#40](https://github.com/jaroslaw-bagnicki/Homelab/issues/40) · [#46](https://github.com/jaroslaw-bagnicki/Homelab/issues/46)
- **(docs)** Add ADR 22 — migrate Homelab workloads to Kubernetes (k3s + Azure Arc) — [ADR 22](docs/decisions/22-k3s-arc-homelab.md)
- **(docs)** Add ADR 21 — per-project OpenCode container images — [ADR 21](docs/decisions/21-opencode-instance-images.md)
- **(docs)** Provisioning runbook for new OpenCode instances — inventory, AKV secret, deploy, model providers — [runbook 18](docs/runbooks/18-provision-opencode-instance.md) · [#37](https://github.com/jaroslaw-bagnicki/Homelab/issues/37) · [#42](https://github.com/jaroslaw-bagnicki/Homelab/issues/42)
- **(feat)** Init server-hosted OpenCode instances on Cloudlab — `docker_opencode_ingress` + `docker_opencode_instances` roles, wildcard `*-oc.<domain>` routing — [runbook 17](docs/runbooks/17-deploy-opencode-on-cloudlab.md) · [#30](https://github.com/jaroslaw-bagnicki/Homelab/issues/30) · [#32](https://github.com/jaroslaw-bagnicki/Homelab/issues/32)
- **(docs)** Research: Infisical for Homelab secret management — [research 22](docs/research/22-infisical-for-homelab-secret-management.md)
- **(docs)** Research: OpenCode sandboxed homelab architecture — [research 21](docs/research/21-opencode-sandboxed-homelab-architecture.md)
- **(docs)** Research: OpenCode hosting — Codespaces vs Homelab vs Cloudlab — [research 20](docs/research/20-opencode-hosting-codespaces-vs-homelab.md)
- **(docs)** Add ADR 18 — host OpenCode server instances on Homelab — [ADR 18](docs/decisions/18-opencode-sandbox.md)
- **(feat)** Add `cloudflared` to `docker_services` — Cloudflare Tunnel as the only ingress, plain-HTTP origin behind Caddy — [runbook 16](docs/runbooks/16-docker-services-ansible-role.md)
- **(feat)** Expose Portainer via `portainer.cloud5.ovh` with injected admin password — [#29](https://github.com/jaroslaw-bagnicki/Homelab/issues/29)
- **(docs)** Document Cloudflare Access policy for admin services
- **(docs)** Document Codespaces secret + `containerEnv` for DeepSeek in the dev container

## 2026‑06

- **(docs)** Add ADR 17 — adopt OpenCode for agentic Homelab development — [ADR 17](docs/decisions/17-adopt-opencode.md)
- **(feat)** OpenCode session persistence + Azure Blob backup — survives Dev Container rebuilds and Codespace deletion — [runbook 15](docs/runbooks/15-opencode-session-persistence.md)
- **(feat)** GH Codespaces service principal for Homelab — enables Azure MCP — [runbook 14](docs/runbooks/14-gh-codespaces-sp-for-homelab.md) · [ADR 16](docs/decisions/16-agent-identity-pattern.md)
- **(docs)** Add ADR 15 — evaluate GitHub Copilot Desktop for agentic development (deferred) — [ADR 15](docs/decisions/15-copilot-desktop-agentic.md)
- **(docs)** Add ADR 14 — adopt GitHub Codespaces for occasional remote work — [ADR 14](docs/decisions/14-codespaces-adoption.md)
- **(feat)** Add `docker_services` Ansible role — deploys Portainer, Caddy, and Hello World on Cloudlab via `docker_compose_v2` — [runbook 16](docs/runbooks/16-docker-services-ansible-role.md) · [#14](https://github.com/jaroslaw-bagnicki/Homelab/issues/14)
- **(docs)** Add ADR 13 — use Contabo Cloud VPS 10 as staging environment — [ADR 13](docs/decisions/13-cloudlab-staging.md)
- **(docs)** Add ADR 12 — lightweight ADR log in MADR format — [ADR 12](docs/decisions/12-establish-adr-log.md)
- **(docs)** Add ADR 11 — GitHub Issues for ticketing — [ADR 11](docs/decisions/11-ticketing-github-issues.md)
- **(docs)** Add ADR 10 — Ansible for host configuration management — [ADR 10](docs/decisions/10-ansible-host-config.md)
- **(docs)** Add ADR 09 — Azure Monitor via Arc — [ADR 09](docs/decisions/09-azure-monitor-via-arc.md)
- **(feat)** Contabo Cloud VPS 10 as Ansible dev/test sandbox — SSH hardening, UFW, fail2ban, Docker — [runbook 10](docs/runbooks/10-vps-playground.md)
- **(feat)** Azure Monitor metrics and log collection on Arc-connected servers — [runbook 06a](docs/runbooks/06a-azure-monitor.md)
- **(docs)** Research: GitHub Codespaces & Dev Containers setup — [research 16](docs/research/16-github-codespaces-devcontainers.md)
- **(docs)** Research: Docker Compose replication options after rebuild — [research 18](docs/research/18-docker-compose-replication.md)

## 2026‑05

- **(feat)** Base setup — Ubuntu 24.04, static IP, SSH, LVM, mDNS, hardening — [runbook 01](docs/runbooks/01-init.md)
- **(feat)** Docker Engine + Portainer CE — [runbook 02](docs/runbooks/02-docker.md)
- **(feat)** Local DNS via DNSMasq — `*.home` wildcard resolution — [runbook 03](docs/runbooks/03-dns.md)
- **(feat)** Caddy reverse proxy with auto-TLS — [runbook 04](docs/runbooks/04-caddy.md)
- **(feat)** Cloudflare Tunnel for remote HTTPS access — [runbook 05](docs/runbooks/05-cloudflare-tunnel.md)
- **(feat)** Azure Arc hybrid server enrollment — cert-based auth — [runbook 06](docs/runbooks/06-azure-arc.md)
- **(feat)** Container registries in Portainer (GHCR) — [runbook 02a](docs/runbooks/02a-ghcr-portainer.md)
- **(feat)** Hello World demo behind Caddy + Cloudflare — [runbook 04a](docs/runbooks/04a-hello-world.md)
- **(docs)** Add ADRs 01–08 — hardware, OS, backup, hybrid cloud, reverse proxy, local DNS, remote access, Azure Monitor — [decision log](docs/decisions/README.md)
- **(docs)** Research 01–18 — hardware, OS, container stack, networking, VPS selection, backup, Copilot Desktop — [research index](docs/research/README.md)
