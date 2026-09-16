# Changelog

Notable changes to the Homelab repo, newest first. This log supersedes the
"What's Done" table that used to live in the root `README.md`. Entries use the
same `(type)` prefixes as commit messages; types: `feat`, `fix`, `docs`, `chore`, `refactor`.

**One line per entry, one entry per PR.** State what changed and link the artefact — the rationale,
measurements and failure stories live in the linked ADR, runbook or report. Notable changes only:
no instruction-file tweaks, roadmap/board edits, typo/link fixes or changelog bookkeeping.

## 2026‑09

- **(docs)** Add the `quality-assessment` prompt + first repo assessment, fixing ADR 19's origin-design contradiction and the Low findings it surfaced — [prompt](.github/prompts/quality-assessment.prompt.md) · [report](docs/reports/260913-quality-assessment.md)
- **(docs)** Add ADR 32 — no hosted CI — [ADR 32](docs/decisions/32-no-hosted-ci.md)
- **(docs)** UPS graceful shutdown via **NUT** in LXC 213 on the HA node (`nutdrv_qx`, triggered on `LB`) + the `upsmon` password script — [ADR 30](docs/decisions/30-ups-nut-graceful-shutdown.md) · [runbook 29](docs/runbooks/29-nut-ups-shutdown.md) · [#111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111)
- **(docs)** Re-cut the static address scheme — `20x` physical servers, `21x` Proxmox guests where **VMID = last octet** (VM 210 · LXC 211/212/213) — [research 24](docs/research/24-network-topology-design.md) · [ADR 31](docs/decisions/31-static-address-scheme.md) · [runbook 29](docs/runbooks/29-nut-ups-shutdown.md)
- **(docs)** Wincor Beetle M-III is the NAS successor on OMV — hardware re-audit + the decision superseding the ML110 — [research 32](docs/research/32-wincor-beetle-m3-hardware-diagnostic.md) · [ADR 29](docs/decisions/29-nas-backup-target-beetle-m3-omv.md) · [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)
- **(docs)** Add idea 09 — shared-rail UPS with NUT-driven graceful shutdown + a Home Assistant NUT integration, with the fleet load profile, Green Cell model comparison and modified-sine risk — [idea 09](docs/ideas/09-ups-nut-home-assistant.md)
- **(feat)** HA node (Wyse 5070) — Proxmox VE **9.2.2** installed (static `.201`), base provisioned and `fleetadm` given `sudo`; HA VM/LXC still open — [hardware](docs/hardware.md) · [runbook 28](docs/runbooks/28-ha-proxmox-node.md) · [#103](https://github.com/jaroslaw-bagnicki/Homelab/issues/103) · [#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104)
- **(feat)** SSH access LAN-only + devcontainer fleet-key autoload — `security` allows LAN password auth for the human breakglass while key-only elsewhere; `profile.ps1` always loads `fleetadm-key-priv` at session start — [runbook 24](docs/runbooks/24-edge-appliance.md) · [#78](https://github.com/jaroslaw-bagnicki/Homelab/issues/78)
- **(docs)** Futro S930 hardware diagnostic — OPNsense router candidate pre-boot audit (research 31) — [research 31](docs/research/31-futro-s930-hardware-diagnostic.md) · [#97](https://github.com/jaroslaw-bagnicki/Homelab/issues/97)

## 2026‑08

- **(docs)** Edge ingress appliance — Wyse 3040: hardware research, ADR 24, the `edge_host` role, Debian install and the backup/restore runbook — [ADR 24](docs/decisions/24-edge-ingress-appliance.md) · [runbook 24](docs/runbooks/24-edge-appliance.md) · [runbook 27](docs/runbooks/27-edge-backup-restore.md) · [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)
- **(docs)** Homelab LTE/5G WAN failover — idea + mobile-internet offer research; Huawei B593u-12 LTE modem added to network appliances — [idea 08](docs/ideas/08-lte-wan-failover.md) · [research 30](docs/research/30-mobile-internet-failover-offers.md) · [#90](https://github.com/jaroslaw-bagnicki/Homelab/issues/90)
- **(docs)** NAS backup-target variants — EliteDesk 800 G1 and Wincor Beetle M-III ideas — [idea 01b](docs/ideas/01b-nas-backup-target-elitedesk.md) · [idea 01c](docs/ideas/01c-nas-backup-target-wincor-beetle.md) · [#89](https://github.com/jaroslaw-bagnicki/Homelab/issues/89)
- **(docs)** Add idea 07 — OPNsense router on a Fujitsu Futro S930 (incl. HP T730 alternative + NIC/5G-failover supplements) — [idea 07](docs/ideas/07-opnsense-futro-s930.md) · [#86](https://github.com/jaroslaw-bagnicki/Homelab/issues/86)
- **(docs)** Wyse 5070 hardware diagnostic — J4105, 2× 4 GB DDR4 (both slots full), M.2 SATA 2280 with SK hynix SC311 128 GB installed, eMMC present but unused, no NVMe (research 29) — [research 29](docs/research/29-wyse5070-hardware-diagnostic.md) · [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)
- **(feat)** Dedicated fleet-wide SSH key for automation — `fleetadm@homelab`, private key in `homelab-bysxdb-kv`, public key committed and re-armed on every host by the `common` role; used by Ansible and AI agent tooling — [ADR 28](docs/decisions/28-fleet-admin-account-and-key.md)
- **(docs)** ML110 NAS — Phase 0 inventory, OMV install (ADR 23, mdadm RAID1) and the SMB `/shared` backup share — [ADR 23](docs/decisions/23-nas-on-ml110.md) · [runbook 23](docs/runbooks/23-ml110-omv-setup.md) · [runbook 26](docs/runbooks/26-ml110-nas-exports.md) · [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
- **(feat)** M910q OS refresh — reinstall Ubuntu 24.04 LTS (ADR 05), Ansible base provision (`playbook-homelab.yml`) and Azure Arc enrolment; DNS/Caddy/tunnel move to the edge appliance (ADR 24) — [runbook 25](docs/runbooks/25-m910q-os-refresh.md) · [#74](https://github.com/jaroslaw-bagnicki/Homelab/issues/74)
- **(docs)** Add ADR 27 — two-tier monitoring: Azure Monitor via Arc (Tier A) + a local stack with Netdata as its first component (Tier B); Grafana/Prometheus/Fluent Bit/Loki are future Tier B components, not adopted — [ADR 27](docs/decisions/27-monitoring-strategy.md) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75)
- **(docs)** Zigbee energy monitoring — ADR 26 + research 27: per-device plugs, protocol comparison and the Z2M → Prometheus path — [ADR 26](docs/decisions/26-zigbee-energy-monitoring.md) · [research 27](docs/research/27-zigbee-energy-monitoring.md) · [idea 06](docs/ideas/06-homelab-energy-monitoring.md)
- **(docs)** Add `docs/overview.md` (nodes, workloads, topology) and `docs/hardware.md` (per-node inventory), making overview the single state + roadmap page — [overview](docs/overview.md) · [hardware](docs/hardware.md)
- **(docs)** Home Assistant on a dedicated thin-client node — Proxmox VE VM + Mosquitto/Zigbee2MQTT — [ADR 25](docs/decisions/25-home-assistant-thin-client.md) · [idea 05](docs/ideas/05-home-assistant-thin-client.md) · [research 26](docs/research/26-home-assistant-thin-client.md)
- **(docs)** Homelab network topology & design — mesh inventory, flat-vs-VLAN analysis, static IP scheme — [research 24](docs/research/24-network-topology-design.md)
- **(docs)** TL-SG108E switch setup — wiring, management IP, QoS/rate-limit, IGMP snooping — [runbook 21](docs/runbooks/21-tl-sg108e-switch.md) · [#55](https://github.com/jaroslaw-bagnicki/Homelab/issues/55)
- **(feat)** Build per-project OpenCode container images (`opencode-homelab`, `opencode-prospera`) and push to the Zot registry — [#52](https://github.com/jaroslaw-bagnicki/Homelab/issues/52)
- **(feat)** Adopt Zot as self-hosted OCI container registry — pull-through cache for GHCR/mcr/Docker Hub — [runbook 20](docs/runbooks/20-deploy-zot.md) · [#50](https://github.com/jaroslaw-bagnicki/Homelab/issues/50) · [#51](https://github.com/jaroslaw-bagnicki/Homelab/issues/51)
- **(feat)** Configure MCP servers per OpenCode instance — GitHub MCP PAT + Azure MCP — [#41](https://github.com/jaroslaw-bagnicki/Homelab/issues/41) · [#47](https://github.com/jaroslaw-bagnicki/Homelab/issues/47)
- **(docs)** Add ideas: DevPod DevContainers for OpenCode ([idea 02](docs/ideas/02-devcontainers-opencode-k3s.md)) and NAS backup target ([idea 01](docs/ideas/01-nas-backup-target.md))
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
- **(feat)** Add `cloudflared` to the `docker_services` role — Cloudflare Tunnel as the only ingress path, with a plain-HTTP origin behind Caddy — [runbook 16](docs/runbooks/16-docker-services-ansible-role.md) · [ADR 19](docs/decisions/19-cloudflare-tunnel-http-origin.md) · [#25](https://github.com/jaroslaw-bagnicki/Homelab/issues/25)
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
